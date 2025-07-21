#!/bin/sh

curl -Ssf https://pkgx.sh | sh

f=$(mktemp)

install() {
  echo "#!/usr/local/bin/pkgx -q! $1" > $f
  sudo install -m 755 $f /usr/local/bin/$1
}

install bun
install bunx

install deno

install node
install npm
install npx

install python
install pip

for x in 3.9 3.10 3.11 3.12 3.13; do
  echo "#!/usr/local/bin/pkgx -q! python@$x" > $f
  sudo install -m 755 $f /usr/local/bin/python$x

  echo '#!/usr/local/bin/pkgx -q! python@3.9 -m pip' > $f
  sudo install -m 755 $f /usr/local/bin/pip$x
done

install uv
install uvx

#TODO support CARGO_HOME and RUSTUP_HOME env vars
cat <<EOF > $f
#!/bin/sh

if [ $0 == "rustup" && $1 == "init" ]; then
  shift
  exec /usr/local/bin/pkgx rustup-init "$@"
fi

if [ ! -f "$HOME/.cargo/bin/rustup" ]; then
  echo "a \`rustup\` toolchain has not been installed" >&2
  echo "run: \`rustup init\`" >&2
  exit 3
fi

source ~/.cargo/env

exec ~/.cargo/bin/"$0" "$@"
EOF
sudo install -m 755 $f /usr/local/bin/rustup
sudo install -m 755 $f /usr/local/bin/cargo
sudo install -m 755 $f /usr/local/bin/rustc

