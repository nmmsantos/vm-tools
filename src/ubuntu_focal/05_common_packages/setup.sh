#!/bin/sh

export DEBIAN_FRONTEND=noninteractive

if dpkg -s ubuntu-standard qemu-guest-agent gnupg patch >/dev/null 2>&1; then
    echo "Nothing to do"
    exit 0
fi

apt-get -y install ubuntu-standard qemu-guest-agent gnupg patch apparmor- update-manager-core-
apt-mark auto gnupg

patch -f /etc/bash.bashrc <<EOF
@@ -32,13 +32,13 @@
 #esac

 # enable bash completion in interactive shells
-#if ! shopt -oq posix; then
-#  if [ -f /usr/share/bash-completion/bash_completion ]; then
-#    . /usr/share/bash-completion/bash_completion
-#  elif [ -f /etc/bash_completion ]; then
-#    . /etc/bash_completion
-#  fi
-#fi
+if ! shopt -oq posix; then
+  if [ -f /usr/share/bash-completion/bash_completion ]; then
+    . /usr/share/bash-completion/bash_completion
+  elif [ -f /etc/bash_completion ]; then
+    . /etc/bash_completion
+  fi
+fi

 # sudo hint
 if [ ! -e "$HOME/.sudo_as_admin_successful" ] && [ ! -e "$HOME/.hushlogin" ] ; then
EOF
