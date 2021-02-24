#!/bin/sh

: ${SSH_KEY=ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDT2l7FkBAZeZHDhB7AwT+Vx6pKjIVBe2fgaMb6x3yoi2iwRsxygnDnkX5CrVsSE8jhUqoZ8k75U4TJyKNimCo+9LdIiDjxwOrRPAXjxEbyvfrISlpdoyOZsRbU/wguXvp7Wa2PEgoQFZa8reetOX8hhgVviO5LTZkZkJxUcrdNkxLJ/GeyYTDadt5OnbfuqYcNLmgt1C96fXW0oZaV/bB5WAA5mLEEzS9FH5jxKI4xLQNBSM3vzVJ2sPLbZ/vHhvthl3/NiSVBXjnX+OA1wEw5+dNs+1eNJCTRt8ba6ye2mCGmpIxsq3nNJkOIf/SYqeELN8lAKejlU36SVZ31/ZvqCWlChhoaTJ0Ck022Pgkbr8miP2kH1LgmNNide5rgF5i+TlFBJg6i7gpudeXqxu0eVtHDueT3615o8c1thStK4vZF+zRlbUoHj/ciLGnU+ZpoAbuwK7HE235bITKcuBJ235Jb5aNd5oUnqQqU4+z249ts9KQYmDbxfVf4cgLB0ZUriJjYZBkTNgaBLkVbwWUuYX8pErgcep3zkUzw+alVVLYvbYPMlFvS5BiE2HRHy7JPBQtOqA2RuFsH6/sqEPNqSMwGLvjwIvwvP5PmHPJOOi8Nz3YxpsfWB+pupVL1xE/3ZtTa17CCrOguEsfK0VDDuXy3xIi9cnt4hJ+yP8+TLw==}

# generate ssh host keys
ssh-keygen -A

if test -z "$SSH_KEY"; then
    exit 0
fi

mkdir -p /root/.ssh
chmod 700 /root/.ssh

tee /root/.ssh/authorized_keys >/dev/null <<EOF
$SSH_KEY
EOF

chmod 600 /root/.ssh/authorized_keys
