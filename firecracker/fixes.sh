# Check current permissions
ls -la /dev/kvm

# Add your user to the kvm group
sudo usermod -aG kvm $USER

# Apply immediately without logout
newgrp kvm

# Verify
groups | grep kvm