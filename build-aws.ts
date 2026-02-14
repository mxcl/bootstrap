#!/usr/bin/env -S deno run -A
import { walk } from "jsr:@std/fs@1/walk";
import { dirname, join, resolve } from "jsr:@std/path@1";
import undent from "https://deno.land/x/outdent@v0.8.0/mod.ts";

const USAGE = undent`
  Build the AWS CLI from source.

  Usage:
    build-aws.ts <version> [--out <dir>]

  Examples:
    build-aws.ts 2.15.24
    build-aws.ts 2.15.24 --out ./out
`;

type Args = {
  version: string;
  outDir: string;
};

function parseArgs(args: string[]): Args {
  let version = "";
  let outDir = "out";

  for (let i = 0; i < args.length; i += 1) {
    const arg = args[i];

    if (arg === "-h" || arg === "--help") {
      console.log(USAGE.trimEnd());
      Deno.exit(0);
    }

    if (arg === "--out" || arg === "--prefix") {
      const value = args[i + 1];
      if (!value || value.startsWith("-")) {
        throw new Error(`missing value for ${arg}`);
      }
      outDir = value;
      i += 1;
      continue;
    }

    if (arg.startsWith("--out=")) {
      outDir = arg.slice("--out=".length);
      continue;
    }

    if (arg.startsWith("--prefix=")) {
      outDir = arg.slice("--prefix=".length);
      continue;
    }

    if (arg.startsWith("-")) {
      throw new Error(`unknown option: ${arg}`);
    }

    if (!version) {
      version = arg;
      continue;
    }

    throw new Error(`unexpected argument: ${arg}`);
  }

  if (!version) {
    throw new Error("missing <version>");
  }

  return { version, outDir };
}

async function runCommand(
  cmd: string[],
  options: { cwd?: string } = {},
): Promise<void> {
  const command = new Deno.Command(cmd[0], {
    args: cmd.slice(1),
    cwd: options.cwd,
    stdin: "inherit",
    stdout: "inherit",
    stderr: "inherit",
  });
  const { success, code } = await command.spawn().status;
  if (!success) {
    throw new Error(`command failed (${code}): ${cmd.join(" ")}`);
  }
}

async function runCommandOutput(
  cmd: string[],
  options: { cwd?: string } = {},
): Promise<string> {
  const command = new Deno.Command(cmd[0], {
    args: cmd.slice(1),
    cwd: options.cwd,
    stdin: "null",
    stdout: "piped",
    stderr: "inherit",
  });
  const { success, code, stdout } = await command.output();
  if (!success) {
    throw new Error(`command failed (${code}): ${cmd.join(" ")}`);
  }
  return new TextDecoder().decode(stdout).trim();
}

async function resolveUv(): Promise<string> {
  const candidates = ["/usr/local/bin/uv", "uv"];

  for (const candidate of candidates) {
    try {
      await runCommandOutput([candidate, "--version"]);
      return candidate;
    } catch {
      continue;
    }
  }

  throw new Error("uv not found (expected /usr/local/bin/uv or uv in PATH)");
}

async function ensureUvPython(version: string): Promise<string> {
  const uv = await resolveUv();
  const findArgs = [uv, "python", "find", "--managed-python", version];
  try {
    return await runCommandOutput(findArgs);
  } catch {
    await runCommand([uv, "python", "install", "--managed-python", version]);
    return await runCommandOutput(findArgs);
  }
}

async function download(url: string, dest: string): Promise<void> {
  console.error("+ downloading:", url);
  const rsp = await fetch(url, {
    headers: { "User-Agent": "pkgx/manifests" },
  });
  if (!rsp.ok || !rsp.body) {
    throw new Error(`download failed: ${url}`);
  }

  await Deno.mkdir(dirname(dest), { recursive: true });
  using file = await Deno.open(dest, {
    write: true,
    create: true,
    truncate: true,
  });
  await rsp.body.pipeTo(file.writable);
}

async function extractTarGz(
  archivePath: string,
  destDir: string,
): Promise<void> {
  await Deno.mkdir(destDir, { recursive: true });
  console.error("+ extracting:", archivePath);
  await runCommand([
    "tar",
    "-xzf",
    archivePath,
    "--strip-components=1",
    "-C",
    destDir,
  ]);
}

function makeBinWrapper(content: string): string {
  return undent`
    #!/bin/sh
    """:"
    d="$(cd "$(dirname "$0")/.." && pwd)"
    exec "$d/share/awscli/bin/python" "$0" "$@"
    ":"""

    ${content}`;
}

async function writeBinEntry(
  shareDir: string,
  binDir: string,
  program: string,
): Promise<void> {
  const sourcePath = join(shareDir, "bin", program);
  const raw = await Deno.readTextFile(sourcePath);
  const content = raw.split("\n").slice(1).join("\n");

  await Deno.mkdir(binDir, { recursive: true });
  const programPath = join(binDir, program);
  const wrapper = makeBinWrapper(content);
  await Deno.writeTextFile(programPath, wrapper);
  await Deno.chmod(programPath, 0o755);
}

async function hardlinkPython(
  venvDir: string,
  pythonBin: string,
  version: string,
): Promise<void> {
  const binDir = join(venvDir, "bin");
  const pythonTarget = await Deno.realPath(pythonBin);
  const linkNames = ["python", "python3", `python${version}`];

  for (const name of linkNames) {
    const linkPath = join(binDir, name);
    await removeIfExists(linkPath);
    await Deno.link(pythonTarget, linkPath);
    await Deno.chmod(linkPath, 0o755);
  }

  const pythonPrefix = dirname(dirname(pythonTarget));
  const sourceLibDir = join(pythonPrefix, "lib");
  const libNames: string[] = [];
  try {
    for await (const entry of Deno.readDir(sourceLibDir)) {
      if (
        entry.isFile &&
        entry.name.startsWith("libpython") &&
        entry.name.endsWith(".dylib")
      ) {
        libNames.push(entry.name);
      }
    }
  } catch (err) {
    if (!(err instanceof Deno.errors.NotFound)) {
      throw err;
    }
  }

  if (libNames.length === 0) {
    throw new Error(`missing libpython in ${sourceLibDir}`);
  }

  const libDir = join(venvDir, "lib");
  await Deno.mkdir(libDir, { recursive: true });
  for (const name of libNames) {
    const libSource = join(sourceLibDir, name);
    const libPath = join(libDir, name);
    await removeIfExists(libPath);
    await Deno.link(libSource, libPath);
  }
}

async function pruneEmptyInclude(prefix: string): Promise<void> {
  const includeDir = join(prefix, "include");
  let includeEntries: Deno.DirEntry[] = [];
  try {
    for await (const entry of Deno.readDir(includeDir)) {
      includeEntries.push(entry);
    }
  } catch (err) {
    if (err instanceof Deno.errors.NotFound) {
      return;
    }
    throw err;
  }

  for (const entry of includeEntries) {
    if (!entry.isDirectory || !entry.name.startsWith("python3")) {
      continue;
    }
    const pythonDir = join(includeDir, entry.name);
    let hasEntries = false;
    for await (const subEntry of Deno.readDir(pythonDir)) {
      hasEntries = true;
      break;
    }
    if (!hasEntries) {
      await removeIfExists(pythonDir);
    }
  }

  let hasIncludeEntries = false;
  for await (const entry of Deno.readDir(includeDir)) {
    hasIncludeEntries = true;
    break;
  }
  if (!hasIncludeEntries) {
    await removeIfExists(includeDir);
  }
}

async function pruneVenv(prefix: string): Promise<void> {
  const libDir = join(prefix, "lib");
  let pythonDir = "";

  try {
    for await (const entry of Deno.readDir(libDir)) {
      if (entry.isDirectory && entry.name.startsWith("python")) {
        pythonDir = join(libDir, entry.name);
        break;
      }
    }
  } catch (err) {
    if (err instanceof Deno.errors.NotFound) {
      return;
    }
    throw err;
  }

  if (!pythonDir) {
    return;
  }

  const rms: string[] = [];
  for await (const entry of walk(pythonDir)) {
    if (entry.isFile && entry.path.endsWith(".h")) {
      rms.push(entry.path);
    }
    if (entry.isDirectory && entry.name === "tests") {
      rms.push(entry.path);
    }
    if (entry.isDirectory && entry.name === "__pycache__") {
      rms.push(entry.path);
    }
  }

  for (const target of rms) {
    await removeIfExists(target);
  }

  const sitePackages = join(pythonDir, "site-packages");
  const distInfoPrefixes = ["pip-", "setuptools-", "wheel-"];
  try {
    for await (const entry of Deno.readDir(sitePackages)) {
      if (!entry.isDirectory || !entry.name.endsWith(".dist-info")) {
        continue;
      }
      if (distInfoPrefixes.some((prefix) => entry.name.startsWith(prefix))) {
        await removeIfExists(join(sitePackages, entry.name));
      }
    }
  } catch (err) {
    if (!(err instanceof Deno.errors.NotFound)) {
      throw err;
    }
  }

  await removeIfExists(join(sitePackages, "setuptools"));
  await removeIfExists(join(sitePackages, "_distutils_hack"));
  await removeIfExists(join(sitePackages, "pip"));
  await removeIfExists(join(sitePackages, "pkg_resources"));
}

async function pruneBinExtras(prefix: string): Promise<void> {
  const binDir = join(prefix, "bin");
  const removePatterns = [
    /^activate(\.|$)/i,
    /^pip(\d|$)/,
    /^easy_install(\d|$)/,
  ];

  try {
    for await (const entry of Deno.readDir(binDir)) {
      if (!entry.isFile && !entry.isSymlink) {
        continue;
      }
      if (!removePatterns.some((pattern) => pattern.test(entry.name))) {
        continue;
      }
      await removeIfExists(join(binDir, entry.name));
    }
  } catch (err) {
    if (!(err instanceof Deno.errors.NotFound)) {
      throw err;
    }
  }
}

async function removeIfExists(path: string): Promise<void> {
  try {
    await Deno.remove(path, { recursive: true });
  } catch (err) {
    if (!(err instanceof Deno.errors.NotFound)) {
      throw err;
    }
  }
}

async function buildAws(version: string, outDir: string): Promise<void> {
  const prefix = resolve(outDir);
  const shareDir = join(prefix, "share", "awscli");
  const binDir = join(prefix, "bin");
  const pythonVersion = "3.12";
  const workDir = await Deno.makeTempDir({ prefix: "aws-cli-build-" });
  const srcDir = join(workDir, "src");
  const archivePath = join(workDir, `aws-cli-${version}.tar.gz`);

  try {
    await download(
      `https://github.com/aws/aws-cli/archive/${version}.tar.gz`,
      archivePath,
    );
    await extractTarGz(archivePath, srcDir);

    await removeIfExists(prefix);
    await Deno.mkdir(dirname(shareDir), { recursive: true });

    const pythonBin = await ensureUvPython(pythonVersion);
    console.error("+ creating venv:", shareDir);
    await runCommand([pythonBin, "-m", "venv", shareDir]);
    await hardlinkPython(shareDir, pythonBin, pythonVersion);

    console.error("+ installing into venv");
    await runCommand(
      [join(shareDir, "bin", "pip"), "install", "--no-cache-dir", "."],
      { cwd: srcDir },
    );

    await writeBinEntry(shareDir, binDir, "aws");
    await pruneVenv(shareDir);
    await pruneEmptyInclude(shareDir);
    await pruneBinExtras(shareDir);

    console.error("+ done:", prefix);
  } finally {
    await removeIfExists(workDir);
  }
}

if (import.meta.main) {
  try {
    const { version, outDir } = parseArgs(Deno.args);
    await buildAws(version, outDir);
  } catch (err) {
    console.error(err instanceof Error ? err.message : err);
    console.error("\n" + USAGE.trimEnd());
    Deno.exit(1);
  }
}
