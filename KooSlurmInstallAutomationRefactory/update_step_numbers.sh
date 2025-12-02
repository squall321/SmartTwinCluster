#!/bin/bash
# Step 번호 업데이트 (9 -> 10)
sed -i 's/Step 1\/9/Step 1\/10/g' setup_cluster_full.sh
sed -i 's/Step 2\/9/Step 2\/10/g' setup_cluster_full.sh
sed -i 's/Step 3\/9/Step 3\/10/g' setup_cluster_full.sh
sed -i 's/Step 4\/9/Step 4\/10/g' setup_cluster_full.sh
sed -i 's/Step 6\/9/Step 6\/10/g' setup_cluster_full.sh
sed -i 's/Step 7\/9/Step 7\/10/g' setup_cluster_full.sh
sed -i 's/Step 8\/9/Step 8\/10/g' setup_cluster_full.sh
sed -i 's/Step 9\/9/Step 9\/10/g' setup_cluster_full.sh

echo "✅ Step 번호 업데이트 완료 (9단계 → 10단계)"
