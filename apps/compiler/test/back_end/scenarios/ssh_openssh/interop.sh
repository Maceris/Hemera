#!/bin/sh
# std/ssh against OpenSSH's ssh, sshd and ssh-keygen, run by linux_tests.py in the folder it copied ssh_openssh to,
# with sshpass installed. Exits 42 if everything worked, and otherwise says what didn't.
set -u
program="$(pwd)/ssh_openssh"
work="$(pwd)/ssh_interop"
rm -rf "$work"
mkdir -p "$work" || exit 1
cd "$work" || exit 1
failures=0
fail() {
    echo "FAILED: $*"
    failures=$((failures + 1))
}

# Keys: a host key it writes, which ssh-keygen has to read, and a user key ssh-keygen writes, which it has to
"$program" keygen host || fail "keygen"
chmod 600 host
[ "$(ssh-keygen -y -f host | cut -d' ' -f1-2)" = "$(cut -d' ' -f1-2 host.pub)" ] || fail "ssh-keygen doesn't read its key"
[ "$("$program" fingerprint host.pub)" = "$(ssh-keygen -lf host.pub | cut -d' ' -f2)" ] || fail "fingerprints differ"
ssh-keygen -q -t ed25519 -N '' -C user@test -f user || fail "ssh-keygen -t ed25519"
echo "hemera $(cat host.pub)" > known_hosts
head -c 1000000 /dev/urandom > data
sum="$(sha256sum < data)"

# OpenSSH's ssh, to it as a server
for kex in mlkem768x25519-sha256 curve25519-sha256; do
    for cipher in chacha20-poly1305@openssh.com aes256-gcm@openssh.com; do
        set -- -F /dev/null -o "ProxyCommand=$program server host user.pub secret" -o UserKnownHostsFile=known_hosts \
            -o StrictHostKeyChecking=yes -o HostKeyAlias=hemera -o KexAlgorithms=$kex -o Ciphers=$cipher \
            -o RekeyLimit=256K -o LogLevel=ERROR
        got="$(ssh "$@" -o BatchMode=yes -o IdentitiesOnly=yes -i user alice@hemera "echo hi")"
        status=$?
        [ "$got" = "ran echo hi" ] && [ $status -eq 7 ] || fail "$kex $cipher: a command with a key gave '$got', $status"
        got="$(ssh "$@" -o BatchMode=yes -o IdentitiesOnly=yes -i user alice@hemera cat < data | sha256sum)"
        [ "$got" = "$sum" ] || fail "$kex $cipher: a megabyte through cat came back changed"
        got="$(sshpass -p secret ssh "$@" -o PubkeyAuthentication=no -o PreferredAuthentications=password \
            alice@hemera "who")"
        [ "$got" = "ran who" ] || fail "$kex $cipher: a password wasn't taken: '$got'"
    done
done
# Users' keys of the other kinds, and RSA signed with SHA-256 as well as SHA-512
for kind in ecdsa:256 rsa:3072; do
    ssh-keygen -q -t "${kind%%:*}" -b "${kind##*:}" -N '' -f "user_${kind%%:*}" || fail "ssh-keygen -t $kind"
done
for login in "ecdsa ecdsa-sha2-nistp256" "rsa rsa-sha2-512" "rsa rsa-sha2-256"; do
    set -- $login
    got="$(ssh -F /dev/null -o "ProxyCommand=$program server host user_$1.pub secret" -o UserKnownHostsFile=known_hosts \
        -o StrictHostKeyChecking=yes -o HostKeyAlias=hemera -o LogLevel=ERROR -o BatchMode=yes -o IdentitiesOnly=yes \
        -o PubkeyAcceptedAlgorithms=$2 -i "user_$1" alice@hemera "who")"
    [ "$got" = "ran who" ] || fail "a $2 key wasn't taken: '$got'"
done
set -- -F /dev/null -o "ProxyCommand=$program server host user.pub secret" -o UserKnownHostsFile=known_hosts \
    -o StrictHostKeyChecking=yes -o HostKeyAlias=hemera -o LogLevel=ERROR
sshpass -p wrong ssh "$@" -o PubkeyAuthentication=no -o PreferredAuthentications=password -o NumberOfPasswordPrompts=1 \
    alice@hemera "who" > /dev/null 2>&1 && fail "a wrong password was taken"
ssh-keygen -q -t ed25519 -N '' -f other || fail "ssh-keygen another"
ssh "$@" -o BatchMode=yes -o IdentitiesOnly=yes -i other alice@hemera "who" > /dev/null 2>&1 && fail "a key not authorized was taken"

# It as a client, of OpenSSH's sshd -i, as this user, through two FIFOs
ssh-keygen -q -t ed25519 -N '' -f sshd_host || fail "ssh-keygen the sshd host key"
cp user.pub authorized
cp sshd_host.pub sshd_known
mkfifo to_sshd from_sshd
for kex in mlkem768x25519-sha256 curve25519-sha256; do
    for cipher in chacha20-poly1305@openssh.com aes256-gcm@openssh.com; do
        cat > sshd_config <<EOF
HostKey $work/sshd_host
AuthorizedKeysFile $work/authorized
UsePAM no
StrictModes no
PidFile none
KexAlgorithms $kex
Ciphers $cipher
RekeyLimit 256K
LogLevel ERROR
EOF
        /usr/sbin/sshd -i -f sshd_config < to_sshd > from_sshd 2>> sshd.log &
        "$program" client "$(id -un)" user sshd_known "echo hello; exit 5" > to_sshd < from_sshd 2> client_out
        status=$?
        wait
        [ "$(cat client_out)" = "hello" ] && [ $status -eq 5 ] || fail "$kex $cipher: a command to sshd gave '$(cat client_out)', $status"
        /usr/sbin/sshd -i -f sshd_config < to_sshd > from_sshd 2>> sshd.log &
        "$program" client "$(id -un)" user sshd_known "sha256sum" data > to_sshd < from_sshd 2> client_out
        status=$?
        wait
        [ "$(cat client_out)" = "$sum" ] && [ $status -eq 0 ] || fail "$kex $cipher: a megabyte to sshd gave '$(cat client_out)', $status"
    done
done
# A host key it doesn't know
/usr/sbin/sshd -i -f sshd_config < to_sshd > from_sshd 2>> sshd.log &
"$program" client "$(id -un)" user host.pub "echo hello" > to_sshd < from_sshd 2> client_out
status=$?
wait
[ $status -eq 100 ] || fail "a host key it doesn't know was taken: $status"

if [ $failures -ne 0 ]; then
    cat sshd.log
    exit 1
fi
exit 42
