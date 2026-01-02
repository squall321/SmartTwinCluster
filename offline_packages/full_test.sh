#!/bin/bash
set -e

echo "=== Full test: Download ALL wheels for Python 3.12 ==="
echo ""

# Create test directory
rm -rf full_test_wheels
mkdir -p full_test_wheels/python3.12
cd full_test_wheels

# Combine all requirements_actual.txt files
echo "Step 1: Combining all requirements_actual.txt files..."
cat /dev/null > combined_requirements.txt

for file in ../../dashboard/*/requirements_actual.txt ../../dashboard/*/backend_*/requirements_actual.txt; do
    if [ -f "$file" ]; then
        service=$(basename $(dirname $file))
        echo "  Adding $service ($(wc -l < $file) packages)"
        cat "$file" >> combined_requirements.txt
    fi
done

echo ""
echo "Step 2: Removing duplicates..."
sort combined_requirements.txt | uniq > combined_requirements_unique.txt
total_lines=$(wc -l < combined_requirements.txt)
unique_lines=$(wc -l < combined_requirements_unique.txt)

echo "  Total lines: $total_lines"
echo "  Unique packages: $unique_lines"
echo ""

echo "Step 3: Downloading wheels for Python 3.12..."
cd python3.12
time python3.12 -m pip download -r ../combined_requirements_unique.txt --dest . 2>&1 | tee download.log

echo ""
echo "=== Download complete ==="
wheel_count=$(find . -name "*.whl" -o -name "*.tar.gz" | wc -l)
total_size=$(du -sh . | cut -f1)

echo ""
echo "Results:"
echo "  Downloaded files: $wheel_count"
echo "  Total size: $total_size"
echo "  Location: $(pwd)"
