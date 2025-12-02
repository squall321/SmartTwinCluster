#!/bin/bash
################################################################################
# Fix Partition Configuration - Remove Debug Partition
# Removes the debug partition to avoid node001 duplication
################################################################################

echo "================================================================================"
echo "🔧 Fixing Partition Configuration"
echo "================================================================================"
echo ""

echo "📋 Current configuration:"
echo "--------------------------------------------------------------------------------"
grep "^PartitionName=" /usr/local/slurm/etc/slurm.conf
echo ""

echo "📋 Current cluster status:"
echo "--------------------------------------------------------------------------------"
sinfo
echo ""

# Backup current configuration
echo "💾 Backing up slurm.conf..."
sudo cp /usr/local/slurm/etc/slurm.conf /usr/local/slurm/etc/slurm.conf.backup.$(date +%Y%m%d_%H%M%S)
echo "✅ Backup created"
echo ""

# Remove debug partition
echo "🗑️  Removing debug partition..."
sudo sed -i '/^PartitionName=debug/d' /usr/local/slurm/etc/slurm.conf
echo "✅ Debug partition removed from configuration"
echo ""

echo "📋 New configuration:"
echo "--------------------------------------------------------------------------------"
grep "^PartitionName=" /usr/local/slurm/etc/slurm.conf
echo ""

# Reconfigure Slurm
echo "🔄 Reconfiguring Slurm..."
sudo scontrol reconfigure
sleep 2
echo "✅ Slurm reconfigured"
echo ""

echo "================================================================================"
echo "✅ Configuration Updated!"
echo "================================================================================"
echo ""

echo "📊 New cluster status:"
echo "--------------------------------------------------------------------------------"
sinfo
echo ""
sinfo -N
echo ""

echo "✅ Done! node001 is now only in the 'normal' partition"
echo ""
echo "Partitions:"
echo "  - normal: node001, node002 (default)"
echo ""
echo "If you need to restore the old config:"
echo "  sudo cp /usr/local/slurm/etc/slurm.conf.backup.* /usr/local/slurm/etc/slurm.conf"
echo "  sudo scontrol reconfigure"
echo ""



