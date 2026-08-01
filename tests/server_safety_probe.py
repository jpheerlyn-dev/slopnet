#!/usr/bin/env python3
"""Static and executable proofs for the server trust boundary.

Nothing here connects to a server. It extracts each embedded remote shell,
asks `sh -n` to parse the exact value that SSH receives, and exercises the
small failure paths that can be proved safely with temporary fake commands.
"""

from importlib.machinery import SourceFileLoader
import hashlib
import io
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import tarfile
import tempfile
from types import SimpleNamespace
from unittest import mock


ROOT = Path(__file__).resolve().parents[1]
failures = 0


def check(ok, what):
    global failures
    print(("ok   " if ok else "FAIL ") + what)
    failures += not ok


def embedded_shell(path, variable, following):
    text = path.read_text(encoding="utf-8")
    start = text.index(f"{variable}=")
    end = text.index(following, start)
    assignment = text[start:end]
    command = assignment + f'\nprintf "%s" "${variable}"\n'
    value = subprocess.run(
        ["bash"], input=command, text=True, capture_output=True, check=True
    ).stdout
    parsed = subprocess.run(["sh", "-n"], input=value, text=True)
    check(parsed.returncode == 0, f"{path.name} sends syntactically valid remote shell")
    return value


def ordered(text, *needles):
    """Return true only when every literal occurs once in the stated order."""
    position = -1
    for needle in needles:
        position = text.find(needle, position + 1)
        if position < 0:
            return False
    return True


def write_executable(path, body):
    path.write_text("#!/bin/sh\n" + body, encoding="utf-8")
    path.chmod(0o755)


packaging = ROOT / "packaging"
onboard_path = packaging / "slopnet-vps-onboard.sh"
uninstall_path = packaging / "slopnet-vps-uninstall.sh"
local_helper_path = packaging / "slopnet-vps-local-helper.sh"

onboard = embedded_shell(onboard_path, "remote_setup", "\nencoded_setup=")
coding = embedded_shell(
    packaging / "slopnet-vps-coding-app.sh", "remote", "\nencoded="
)
uninstall = embedded_shell(uninstall_path, "remote", "\nencoded=")
authorize = embedded_shell(
    onboard_path, "remote_authorize", "\n/usr/bin/printf '%s\\n' \"$validated_public_line\""
)
project = embedded_shell(
    packaging / "slopnet-vps-project.sh", "remote_project", "\nencoded_project="
)
build = embedded_shell(
    packaging / "slopnet-vps-build.sh", "remote_build", "\nencoded_build="
)
chat = embedded_shell(
    packaging / "slopnet-vps-chat.sh", "remote_chat", "\nencoded_chat="
)
local_helper = embedded_shell(
    local_helper_path, "remote_setup", "\nencoded_setup="
)

remote_helpers = (
    ("server setup", onboard),
    ("provider sign-in", coding),
    ("approved build", build),
    ("private guide", chat),
    ("project planning", project),
    ("local-guide setup", local_helper),
    ("uninstall", uninstall),
)
runtime_identity = (
    "kind=runtime-account-v2\\nname=slopnet\\nuid=%s\\ngid=%s\\n"
    "home=/home/slopnet\\nshell=/usr/sbin/nologin\\n"
    "home_dev=%s\\nhome_ino=%s"
)
install_identity = (
    "kind=install-v2\\npath=/opt/slopnet\\ndev=%s\\nino=%s\\n"
    "release=%s\\ncommit=%s"
)
for helper_name, remote in remote_helpers:
    check(runtime_identity in remote and install_identity in remote,
          f"{helper_name} binds receipts to every v2 identity field")
    # A v1 name is never ownership on its own. It may appear only in the
    # upgrade that retires it, which has to prove the receipt is a root-owned
    # ordinary file before it changes anything and has to delete it afterwards,
    # so it cannot be presented twice. Banning the names outright left every
    # installation made before v2 unusable with no way forward but to archive
    # it by hand, which is the work this app exists to remove.
    legacy_named = "runtime-account-v1" in remote or "install-v1" in remote
    legacy_only_upgrades = (not legacy_named) or (
        "upgrade_from_v1" in remote and
        'safe_marker "$managed/runtime-account-v1"' not in remote and
        'safe_marker "$managed/install-v1"' not in remote and
        ordered(remote, "upgrade_from_v1() {", 'stat -c %u "$legacy"',
                'rm -f "$managed/runtime-account-v1" "$managed/install-v1"'))
    check("runtime-account-v2" in remote and "install-v2" in remote and
          legacy_only_upgrades,
          f"{helper_name} takes ownership only from v2 receipts, and retires v1 ones")

check("An unmarked slopnet account already exists" in onboard,
      "setup refuses to adopt an account by name alone")
check("An unmarked /opt/slopnet folder already exists" in onboard,
      "setup refuses to adopt an install folder by name alone")
check("The SlopNet management folder is not a protected root-owned directory" in onboard and
      "The slopnet account is absent but /home/slopnet already belongs" in onboard,
      "setup refuses a forgeable receipt directory or an unrelated runtime home")
check("git clone --quiet --no-checkout" in onboard and
      "chown -R root:root" in onboard and "remote get-url origin" in onboard,
      "root setup uses a fresh, origin-checked, root-owned checkout")
check(ordered(onboard, 'unknown=$(find "$managed"',
              "contains an unknown or legacy receipt", "fresh=$(mktemp"),
      "setup refuses unknown receipts before publishing or running code")
check("fetch --quiet" not in coding and "checkout --quiet" not in coding and
      "diff --quiet" in coding and "rev-parse HEAD" in coding,
      "provider sign-in validates the installed release instead of drifting it")
check("release-v1" in onboard and 'expected_release="release=$slopnet_release"' in onboard,
      "setup records the exact installed release in a protected marker")
for helper_name, remote in remote_helpers:
    check("-perm /022" in remote,
          f"{helper_name} rejects writable identity state")
check("protected_file /opt/slopnet/slopnet" in build and
      "protected_file /opt/slopnet/crew.py" in build and
      "protected_file /opt/slopnet/slopnet" in project and
      "protected_file /opt/slopnet/crew.py" in project,
      "planning and builds execute only protected root-owned SlopNet code")
check("rev-parse HEAD" in build and "diff --quiet" in build and
      "rev-parse HEAD" in project and "diff --quiet" in project,
      "planning and builds validate the tagged checkout before execution")
check("not marked as SlopNet-managed" not in uninstall and
      "protected ownership receipt" in uninstall,
      "uninstall names the v2 receipt boundary in its refusals")
check(".slopnet-plan.XXXXXX" in project and
      'mv "$project_root" "$final_project_root"' in project,
      "planning publishes its project folder only after the plan succeeds")
check("[ ! -s /opt/slopnet/.slopnet/crew.json ]" in project,
      "planning refuses an empty, unproved crew choice")

python_source = (ROOT / "slopnet").read_text(encoding="utf-8")
check('VPS_ACCOUNT_MARKER = VPS_MANAGED_DIRECTORY / "runtime-account-v2"' in python_source and
      'VPS_INSTALL_MARKER = VPS_MANAGED_DIRECTORY / "install-v2"' in python_source,
      "Python bootstrap names only the v2 ownership receipts")
check('"kind=runtime-account-v2\\n"' in python_source and
      'f"uid={entry.pw_uid}\\n"' in python_source and
      'f"gid={entry.pw_gid}\\n"' in python_source and
      'f"home_dev={home_state.st_dev}\\n"' in python_source and
      'f"home_ino={home_state.st_ino}\\n"' in python_source and
      '"kind=install-v2\\n"' in python_source and
      'f"dev={target_state.st_dev}\\n"' in python_source and
      'f"ino={target_state.st_ino}\\n"' in python_source and
      'f"release={release}\\n"' in python_source and
      'f"commit={commit}\\n"' in python_source,
      "Python and shell receipts share account, inode, release and commit identity")
check('os.path.lexists("/home/slopnet")' in python_source and
      'crew_directory.mkdir(mode=0o755' in python_source and
      'os.O_CREAT | os.O_EXCL' in python_source,
      "Python bootstrap refuses home adoption and creates only its narrow crew handoff")
check(ordered(uninstall, "expected_account=$(runtime_receipt)",
              "safe_marker /var/lib/slopnet/runtime-account-v2", "userdel -r slopnet"),
      "uninstall validates the marked account identity before userdel")
check(".slopnet-archive-v1" in onboard and ".slopnet-archive-v1" in uninstall and
      '[ "$(cat "$archive_marker")" = "archive=$archive" ]' in uninstall,
      "only exactly marked root-owned recovery copies are removed")
approved_identity = "kind=approved-build-v1\\nrelease=%s\\ncommit=%s"
check(approved_identity in build and approved_identity in onboard and
      approved_identity in uninstall and
      ordered(onboard, 'safe_marker "$approved_marker"',
              'mv "$approved_marker" "$archive/.slopnet-approved-build-v1"') and
      ordered(uninstall, "approved_build=$(printf",
              "safe_marker /var/lib/slopnet/approved-build-v1", "pkill -u slopnet"),
      "setup and uninstall prove the approved-build marker before archive or deletion")
check('grep -qxF -- "$public_key"' in uninstall and
      'getent passwd "$login_user"' in uninstall and 'grep -q "slopnet-vps"' not in uninstall,
      "uninstall removes only the exact dedicated key from the login account")
check('ssh_opts=(' in uninstall_path.read_text(encoding="utf-8") and
      'ssh_opts+=(-i "$key_path")' in uninstall_path.read_text(encoding="utf-8") and
      '-o PubkeyAuthentication=no' in uninstall_path.read_text(encoding="utf-8") and
      uninstall_path.read_text(encoding="utf-8").count(
          '/usr/bin/ssh "${ssh_opts[@]}"') == 2,
      "uninstall preserves every optional SSH argument in a Bash array")
check(ordered(uninstall, 'unknown=$(find /var/lib/slopnet',
              'contains an unknown file', "pkill -u slopnet", "userdel -r slopnet"),
      "uninstall refuses unknown receipt state before killing or deleting the account")

for script_name in ("slopnet-vps-onboard.sh", "slopnet-vps-coding-app.sh",
                    "slopnet-vps-build.sh", "slopnet-vps-chat.sh",
                    "slopnet-vps-project.sh", "slopnet-vps-local-helper.sh",
                    "slopnet-vps-uninstall.sh"):
    source = (packaging / script_name).read_text(encoding="utf-8")
    check("IdentitiesOnly=yes" in source and "-i " in source and "key_path" in source,
          f"{script_name} pins the dedicated SlopNet SSH identity")
    check(('known_hosts_path="$HOME/.ssh/slopnet_vps_known_hosts"' in source or
           'known_hosts_path="$ssh_dir/slopnet_vps_known_hosts"' in source) and
          "UserKnownHostsFile=$known_hosts_path" in source,
          f"{script_name} sends every SSH connection to dedicated host trust")
    check(ordered(source, "set -euo pipefail", "PATH=/usr/bin:/bin:/usr/sbin:/sbin",
                  "key_path="),
          f"{script_name} fixes a trusted local PATH before key or network decisions")
    payload_mode = "0555" if script_name == "slopnet-vps-project.sh" else "600"
    check("/usr/bin/ssh" in source and "f=\\$(/usr/bin/mktemp" in source and
          '/usr/bin/printf \\"%s\\" \\"\\$1\\" | /usr/bin/base64 -d' in source and
          f'/bin/chmod {payload_mode} \\"\\$f\\"' in source,
          f"{script_name} uses absolute outer tools and a private payload")
    check("/usr/bin/sudo /bin/sh -c 'set -eu; umask 077; f=\\$(/usr/bin/mktemp" in source and
          "&& sudo /bin/sh" not in source and "&& sudo sh" not in source,
          f"{script_name} makes root create the payload before privileged execution")

project_source = (packaging / "slopnet-vps-project.sh").read_text(encoding="utf-8")
check("/bin/chmod 0555" in project_source and
      "/usr/sbin/runuser -u slopnet -- /usr/bin/env HOME=/home/slopnet" in project_source,
      "planning executes the protected root-created payload as the locked runtime account")

# The source installer deliberately cannot run: build_app resolves the pinned
# tag and replaces this empty value with its immutable commit in the bundle.
onboard_source = onboard_path.read_text(encoding="utf-8")
launcher_source = (packaging / "SlopNetLauncher.m").read_text(encoding="utf-8")
settings_source = (packaging / "SlopNetSettings.m").read_text(encoding="utf-8")
tools_source = (packaging / "SlopNetTools.m").read_text(encoding="utf-8")
wizard_source = (packaging / "SlopNetWizard.m").read_text(encoding="utf-8")
build_app_source = (packaging / "build_app.sh").read_text(encoding="utf-8")
build_dmg_path = packaging / "build_dmg.sh"
build_dmg_source = build_dmg_path.read_text(encoding="utf-8")
check("kind=slopnet-ssh-key-v1" in onboard_source and
      all(field in onboard_source for field in
          ("private_dev=", "private_ino=", "public_dev=", "public_ino=",
           "private_sha256=", "public_sha256=", "public_line=%s")) and
      "ssh-keygen -y -P ''" in onboard_source and "cmp -s" in onboard_source,
      "setup reuses only an exact receipt-bound Ed25519 private/public pair")
check("kind=slopnet-known-hosts-v1" in onboard_source and
      "SlopNetProvedKeyPair" in launcher_source and
      "SlopNetProvedKnownHosts" in launcher_source and '@"-R"' not in launcher_source,
      "Mac-only removal deletes only receipt-proved SSH files and never global trust")
check(all("UserKnownHostsFile=" in source for source in
          (launcher_source, settings_source, tools_source, wizard_source)) and
      "/usr/bin/nc" in wizard_source and "UserKnownHostsFile=/dev/null" not in wizard_source,
      "authenticated Mac SSH uses dedicated trust; pre-onboarding uses only TCP reachability")
check('slopnet_commit=""' in onboard_source and
      '[[ "$slopnet_commit" =~ ^[0-9a-f]{40,64}$ ]]' in onboard_source and
      ordered(onboard, 'printf "%s" "$pinned_commit"',
              'rev-parse "refs/tags/$slopnet_release^{commit}"',
              'mv "$fresh/repo" /opt/slopnet'),
      "server setup validates the injected commit before publishing the checkout")
check('rev-parse --verify \\\n    "refs/tags/$slopnet_release^{commit}"' in build_app_source and
      'sed "s/^slopnet_commit=\\"\\"$/slopnet_commit=\\"$slopnet_commit\\"/"' in build_app_source and
      'grep -qx "slopnet_commit=\\"$slopnet_commit\\""' in build_app_source,
      "app packaging injects and verifies the immutable release commit")
check('diff --name-only "refs/tags/$pinned" -- "${bundle_paths[@]}"' in build_dmg_source and
      "packaging/SlopNetEntryView.m" in build_dmg_source and
      'diff --name-only "refs/tags/$pinned" -- "${server_paths[@]}"' in build_dmg_source,
      "disc-image gate compares the pinned tag with server and Mac worktree inputs")

# Exercise the historical stale-tag boundary in an isolated repository. The
# fake hdiutil only gets the script past its availability check; a dirty server
# helper must stop the build before hdiutil or build_app can run.
with tempfile.TemporaryDirectory() as raw:
    release_repo = Path(raw) / "release"
    release_packaging = release_repo / "packaging"
    release_packaging.mkdir(parents=True)
    (release_packaging / "build_dmg.sh").write_text(build_dmg_source,
                                                    encoding="utf-8")
    (release_packaging / "slopnet-vps-onboard.sh").write_text(
        '#!/bin/sh\nslopnet_release="v1.2.3"\n', encoding="utf-8"
    )
    fake_bin = release_repo / "fake-bin"
    fake_bin.mkdir()
    hdiutil_called = release_repo / "hdiutil-called"
    write_executable(fake_bin / "hdiutil", ': > "$HDIUTIL_CALLED"\nexit 99\n')
    subprocess.run(["git", "init", "-q"], cwd=release_repo, check=True)
    subprocess.run(["git", "config", "user.name", "probe"], cwd=release_repo,
                   check=True)
    subprocess.run(["git", "config", "user.email", "probe@slopnet"],
                   cwd=release_repo, check=True)
    subprocess.run(["git", "add", "."], cwd=release_repo, check=True)
    subprocess.run(["git", "commit", "-qm", "release"], cwd=release_repo,
                   check=True)
    subprocess.run(["git", "tag", "v1.2.3"], cwd=release_repo, check=True)
    with (release_packaging / "slopnet-vps-onboard.sh").open("a",
                                                              encoding="utf-8") as helper:
        helper.write("# uncommitted server fix\n")
    dirty_build = subprocess.run(
        ["bash", str(release_packaging / "build_dmg.sh"), str(release_repo)],
        cwd=release_repo,
        env={**os.environ, "PATH": str(fake_bin) + os.pathsep + os.defpath,
             "HDIUTIL_CALLED": str(hdiutil_called)},
        text=True, capture_output=True,
    )
    check(dirty_build.returncode != 0 and
          "uncommitted changes" in dirty_build.stderr and
          not hdiutil_called.exists(),
          "disc-image gate rejects an uncommitted server fix before packaging")
with tempfile.TemporaryDirectory() as raw:
    result = subprocess.run(
        ["bash", str(onboard_path), "example.invalid", "22", "tester"],
        env={**os.environ, "HOME": raw}, text=True, capture_output=True,
    )
    check(result.returncode != 0 and "no verified server commit" in result.stderr and
          not (Path(raw) / ".ssh").exists(),
          "an unbundled installer fails before creating a key or contacting a server")


def bundled_installer(directory):
    installer = directory / "slopnet-vps-onboard.sh"
    installer.write_text(
        onboard_source.replace('slopnet_commit=""', 'slopnet_commit="' + "a" * 40 + '"', 1),
        encoding="utf-8",
    )
    return installer


def run_installer(installer, home):
    return subprocess.run(
        ["bash", str(installer), "127.0.0.1", "1", "tester"],
        env={**os.environ, "HOME": str(home), "TERM": "xterm"},
        text=True, capture_output=True,
    )


# Real entry-point failures: redirected folders and filename collisions stop
# before Step 2, so no SSH connection is even announced and nothing is adopted.
with tempfile.TemporaryDirectory() as raw:
    temporary = Path(raw)
    home = temporary / "home"
    home.mkdir()
    redirected = temporary / "redirected"
    redirected.mkdir()
    (home / ".ssh").symlink_to(redirected, target_is_directory=True)
    result = run_installer(bundled_installer(temporary), home)
    check(result.returncode != 0 and "redirected" in result.stderr and
          "Step 2 of 3" not in result.stdout and not any(redirected.iterdir()),
          "setup refuses a redirected .ssh folder before writes or network")

with tempfile.TemporaryDirectory() as raw:
    temporary = Path(raw)
    home = temporary / "home"
    ssh_dir = home / ".ssh"
    ssh_dir.mkdir(parents=True, mode=0o700)
    collision = ssh_dir / "slopnet_vps_ed25519"
    collision.write_text("somebody else's key\n", encoding="utf-8")
    collision.chmod(0o600)
    result = run_installer(bundled_installer(temporary), home)
    check(result.returncode != 0 and "complete proved set" in result.stderr and
          collision.read_text(encoding="utf-8") == "somebody else's key\n" and
          not collision.with_suffix(".pub").exists() and "Step 2 of 3" not in result.stdout,
          "setup never adopts or completes a same-named private-key collision")

with tempfile.TemporaryDirectory() as raw:
    temporary = Path(raw)
    home = temporary / "home"
    ssh_dir = home / ".ssh"
    ssh_dir.mkdir(parents=True, mode=0o700)
    unrelated = temporary / "unrelated-known-hosts"
    unrelated.write_text("leave me\n", encoding="utf-8")
    (ssh_dir / "slopnet_vps_known_hosts").symlink_to(unrelated)
    result = run_installer(bundled_installer(temporary), home)
    check(result.returncode != 0 and "known-hosts" in result.stderr and
          unrelated.read_text(encoding="utf-8") == "leave me\n" and
          not (ssh_dir / "slopnet_vps_ed25519").exists() and
          "Step 2 of 3" not in result.stdout,
          "setup refuses redirected dedicated host trust before generating a key")

# Let the real installer generate a key, stopping only at a closed localhost
# port. The resulting sidecars are then checked independently and a public-key
# mismatch must be rejected before a second connection attempt.
with tempfile.TemporaryDirectory() as raw:
    temporary = Path(raw)
    home = temporary / "home"
    home.mkdir()
    installer = bundled_installer(temporary)
    first = run_installer(installer, home)
    key = home / ".ssh/slopnet_vps_ed25519"
    public = Path(str(key) + ".pub")
    receipt = Path(str(key) + ".receipt")
    receipt_ok = False
    if all(path.exists() for path in (key, public, receipt)):
        derivation = subprocess.run(
            ["/usr/bin/ssh-keygen", "-y", "-P", "", "-f", str(key)],
            text=True, capture_output=True,
        )
        # Whether ssh-keygen -y prints the comment differs between OpenSSH
        # versions, and assuming it does not put "slopnet-vps" in twice here,
        # so the expected line came out wrong while the installer was right.
        # The public file itself is the line; that it really belongs to this
        # private key is checked separately, on the key material alone.
        public_line = public.read_text(encoding="utf-8").strip()
        derived_material = derivation.stdout.strip().split()[:2]
        public_material = public_line.split()[:2]
        expected_receipt = (
            "kind=slopnet-ssh-key-v1\n"
            f"private_dev={key.stat().st_dev}\nprivate_ino={key.stat().st_ino}\n"
            f"public_dev={public.stat().st_dev}\npublic_ino={public.stat().st_ino}\n"
            f"private_sha256={hashlib.sha256(key.read_bytes()).hexdigest()}\n"
            f"public_sha256={hashlib.sha256(public.read_bytes()).hexdigest()}\n"
            f"public_line={public_line}\n"
        )
        receipt_ok = (
            first.returncode != 0 and derivation.returncode == 0 and
            derived_material == public_material and
            public_line.endswith(" slopnet-vps") and
            receipt.read_text(encoding="utf-8") == expected_receipt and
            all(stat.S_IMODE(path.stat().st_mode) == 0o600
                for path in (key, public, receipt))
        )
        public.write_text("ssh-ed25519 AAAA slopnet-vps\n", encoding="utf-8")
    second = run_installer(installer, home)
    check(receipt_ok and second.returncode != 0 and "do not match" in second.stderr and
          "Step 2 of 3" not in second.stdout,
          "generated Ed25519 pair has an exact receipt and mismatches fail before network")

# Execute the exact atomic append fragment against a valid file lacking its
# final LF. Its old bytes remain a complete line and the new key becomes a
# separate line; neither login key is concatenated or invalidated.
append_start = authorize.index("temporary=$(/usr/bin/mktemp")
append_end = authorize.index("\ntrap - EXIT HUP INT TERM", append_start)
append_fragment = authorize[append_start:append_end + len("\ntrap - EXIT HUP INT TERM")]
with tempfile.TemporaryDirectory() as raw:
    ssh_dir = Path(raw)
    keys = ssh_dir / "authorized_keys"
    old_key = b"ssh-ed25519 T0xE old-key"
    new_key = "ssh-ed25519 TkVX slopnet-vps"
    keys.write_bytes(old_key)
    result = subprocess.run(
        ["/bin/sh", "-c", append_fragment],
        env={**os.environ, "ssh_dir": str(ssh_dir), "keys": str(keys), "key": new_key},
        text=True, capture_output=True,
    )
    check(result.returncode == 0 and
          keys.read_bytes() == old_key + b"\n" + new_key.encode() + b"\n" and
          stat.S_IMODE(keys.stat().st_mode) == 0o600,
          "authorized_keys atomic update separates a new key after a missing final LF")


# Exercise an invalid port through the real uninstall entry point. A fake SSH
# command is present solely to prove the script stops before it could connect.
invalid_port_results = []
with tempfile.TemporaryDirectory() as raw:
    temporary = Path(raw)
    fake_bin = temporary / "bin"
    fake_bin.mkdir()
    ssh_called = temporary / "ssh-called"
    write_executable(fake_bin / "ssh", ': > "$SSH_CALLED"\nexit 99\n')
    environment = {
        **os.environ,
        "HOME": str(temporary / "home"),
        "PATH": str(fake_bin) + os.pathsep + os.defpath,
        "SSH_CALLED": str(ssh_called),
    }
    for invalid_port in ("0", "65536", "22x"):
        result = subprocess.run(
            ["bash", str(uninstall_path), "example.invalid", invalid_port, "tester"],
            input="y\n", env=environment, text=True, capture_output=True,
        )
        invalid_port_results.append(
            result.returncode == 2 and "port must be a number" in result.stderr and
            "Removing SlopNet" not in result.stdout
        )
    check(all(invalid_port_results) and not ssh_called.exists(),
          "invalid low, high and nonnumeric ports fail before approval or SSH")


# Exercise the Python bootstrap at its unknown-receipt boundary. The temporary
# folder is made to look root-owned because the test itself must never need
# root; execution must stop while enumerating receipts, before install/account
# lookups or mutation.
module = SourceFileLoader("slopnet_probe_module", str(ROOT / "slopnet")).load_module()


class BoundaryHit(Exception):
    pass


with tempfile.TemporaryDirectory() as raw:
    managed = Path(raw)
    (managed / "runtime-account-v1").write_text("legacy\n", encoding="utf-8")
    original_lstat = Path.lstat

    def protected_managed_lstat(path):
        if path == managed:
            return SimpleNamespace(st_mode=stat.S_IFDIR | 0o755, st_uid=0)
        return original_lstat(path)

    def boundary_fail(title, *_details):
        raise BoundaryHit(title)

    try:
        with mock.patch.object(module, "VPS_MANAGED_DIRECTORY", managed), \
             mock.patch.object(module, "VPS_INSTALL_MARKER", managed / "install-v2"), \
             mock.patch.object(module, "VPS_ACCOUNT_MARKER", managed / "runtime-account-v2"), \
             mock.patch.object(module.sys, "platform", "linux"), \
             mock.patch.object(Path, "lstat", protected_managed_lstat), \
             mock.patch.object(module, "fail", boundary_fail):
            module.bootstrap_vps_account(Path("/opt/slopnet"))
    except BoundaryHit as stopped:
        check("unknown receipt" in str(stopped).lower(),
              "Python bootstrap refuses a legacy or unknown receipt before mutation")
    else:
        check(False, "Python bootstrap refuses a legacy or unknown receipt before mutation")


tools = json.loads((packaging / "tools.json").read_text(encoding="utf-8"))["tools"]
by_id = {tool["id"]: tool for tool in tools}
versions = {
    "zellij": "0.44.3", "btop": "1.4.7", "lazygit": "0.63.1",
    "superfile": "1.6.0", "lazydocker": "0.25.2", "delta": "0.19.2",
}
near_versions = {
    "zellij": "zellij 0.44.30",
    "btop": "btop version: 1.4.70+f7b2e8a",
    "lazygit": "commit=probe, version=0.63.10, os=linux, arch=amd64, build=probe",
    "superfile": "superfile version v1.6.00",
    "lazydocker": "Version: 0.25.20",
    "delta": "delta 0.19.20",
}


def recipe_parts(install):
    binary_match = re.search(r"(?:^|; )binary=([a-z0-9-]+);", install)
    digest_match = re.search(r"(?:^|; )digest=([0-9a-f]{64});", install)
    if not binary_match or not digest_match:
        raise ValueError("pinned recipe has no binary or digest")
    return binary_match.group(1), digest_match.group(1)


def fake_recipe_environment(temporary, digest, package):
    fake_bin = temporary / "fake-bin"
    fake_bin.mkdir()
    write_executable(
        fake_bin / "uname",
        'case "$1" in -s) printf "Linux\\n" ;; -m) printf "x86_64\\n" ;; *) exit 2 ;; esac\n',
    )
    write_executable(
        fake_bin / "curl",
        'out=\nwhile [ "$#" -gt 0 ]; do\n'
        '  if [ "$1" = -o ]; then shift; out=$1; fi\n'
        '  shift\n'
        'done\n'
        '[ -n "$out" ] || exit 2\ncp "$FAKE_PACKAGE" "$out"\n',
    )
    write_executable(
        fake_bin / "sha256sum",
        'printf "%s  %s\\n" "$FAKE_DIGEST" "$1"\n',
    )
    home = temporary / "home"
    (home / ".local/bin").mkdir(parents=True)
    return {
        **os.environ,
        "HOME": str(home),
        "TMPDIR": str(temporary),
        "PATH": str(fake_bin) + os.pathsep + os.defpath,
        "FAKE_DIGEST": digest,
        "FAKE_PACKAGE": str(package),
    }, home, fake_bin


def prove_bad_digest(tool_id, install):
    binary, _digest = recipe_parts(install)
    with tempfile.TemporaryDirectory() as raw:
        temporary = Path(raw)
        package = temporary / "download"
        package.write_bytes(b"not the proved archive")
        environment, home, fake_bin = fake_recipe_environment(
            temporary, "0" * 64, package
        )
        crossed_digest = temporary / "crossed-digest"
        environment["CROSSED_DIGEST"] = str(crossed_digest)
        write_executable(fake_bin / "file", ': > "$CROSSED_DIGEST"\nexit 99\n')
        write_executable(fake_bin / "tar", ': > "$CROSSED_DIGEST"\nexit 99\n')
        target = home / ".local/bin" / binary
        target.write_text("original\n", encoding="utf-8")
        target.chmod(0o755)
        result = subprocess.run(
            ["sh", "-c", install], env=environment, text=True, capture_output=True
        )
        return (result.returncode != 0 and target.read_text(encoding="utf-8") == "original\n"
                and not crossed_digest.exists())


def prove_near_version(tool_id, install, near_version):
    binary, digest = recipe_parts(install)
    with tempfile.TemporaryDirectory() as raw:
        temporary = Path(raw)
        package = temporary / "candidate.tar.gz"
        candidate_body = (
            "#!/bin/sh\n"
            ': > "$FAKE_EXEC_MARKER"\n'
            'printf "%s\\n" "$FAKE_VERSION_OUTPUT"\n'
        ).encode("utf-8")
        with tarfile.open(package, "w:gz") as archive:
            member = tarfile.TarInfo(binary)
            member.mode = 0o755
            member.size = len(candidate_body)
            archive.addfile(member, io.BytesIO(candidate_body))
        environment, home, _fake_bin = fake_recipe_environment(
            temporary, digest, package
        )
        executed = temporary / "candidate-executed"
        environment["FAKE_EXEC_MARKER"] = str(executed)
        environment["FAKE_VERSION_OUTPUT"] = near_version
        target = home / ".local/bin" / binary
        target.write_text("original\n", encoding="utf-8")
        target.chmod(0o755)
        # The shipped recipe pins PATH to system directories, deliberately, so
        # a privileged payload cannot be steered by whatever is on the caller's
        # path. That also puts the controlled tools below out of reach, so this
        # run — and only this run — prepends them. The pin itself is asserted
        # separately just above, so the property is not lost by testing around
        # it. What is under test here is the order of the checks: that a
        # candidate is run and rejected on its version before anything replaces
        # the command already installed.
        drivable = install.replace("PATH=/usr/bin:/bin",
                                   f"PATH={environment['PATH']}", 1)
        result = subprocess.run(
            ["sh", "-c", drivable], env=environment, text=True, capture_output=True
        )
        return (result.returncode != 0 and executed.exists() and
                target.read_text(encoding="utf-8") == "original\n")


for tool_id, version in versions.items():
    install = by_id[tool_id]["install"]
    check("PATH=/usr/bin:/bin" in install and "export PATH" in install,
          f"{tool_id} pins its path to system directories before doing anything")
    binary, digest = recipe_parts(install)
    check("$(uname -s)" in install and "$(uname -m)" in install and
          version in install and re.fullmatch(r"[0-9a-f]{64}", digest) and
          ordered(install, "curl -fsSL", "actual_digest=$(sha256sum", 
                  'if [ "$actual_digest" != "$digest" ]', 'file "$work/pkg"',
                  'tar -xzf "$work/pkg"', 'install -m 755',
                  '"$stage" --version', 'mv -fT -- "$stage"'),
          f"{tool_id} authenticates bytes before extract, execute and replacement")
    check(prove_bad_digest(tool_id, install),
          f"{tool_id} stops a bad digest before archive handling or replacement")
    check(prove_near_version(tool_id, install, near_versions[tool_id]),
          f"{tool_id} rejects a near-match version and preserves the installed command")
check(by_id["lazydocker"]["run"] == "",
      "LazyDocker cannot cross the locked account's Docker boundary")


# Run the exact challenge-result predicate from the remote helper. An echoed
# sentence containing the answer must not count; an answer on its own line can.
predicate_start = local_helper.index(
    'if ! printf "%s\\n" "$proof_output" | grep -Fx -- "$expected_answer"'
)
predicate_end = local_helper.index("\n\nconfig_dir=", predicate_start)
challenge_predicate = local_helper[predicate_start:predicate_end]
expected_answer = "fedcba9876543210"
echo_only = subprocess.run(
    ["sh", "-c", challenge_predicate],
    env={**os.environ, "expected_answer": expected_answer,
         "proof_output": "The requested token is " + expected_answer + "."},
    text=True, capture_output=True,
)
exact_line = subprocess.run(
    ["sh", "-c", challenge_predicate],
    env={**os.environ, "expected_answer": expected_answer,
         "proof_output": "model banner\n" + expected_answer + "\nfinished"},
    text=True, capture_output=True,
)
check(echo_only.returncode != 0 and exact_line.returncode == 0 and
      "grep -Fx" in challenge_predicate,
      "local-helper proof rejects prompt-like echo and accepts only an exact answer line")

print("\nSERVER SAFETY PROBE DONE — " +
      ("all ok" if failures == 0 else f"{failures} failed"))
raise SystemExit(0 if failures == 0 else 1)
