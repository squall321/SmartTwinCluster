#!/bin/bash
set -e

echo "=== Testing wheel download ==="
echo ""

# Find all requirements files
echo "Step 1: Finding all requirements files..."
find ../dashboard -name "requirements_actual.txt" -o -name "requirements.txt" -o -name "autowebserverrequirements.txt" | grep -v backup | grep -v utf8 | sort

echo ""
echo "Step 2: Counting unique packages across all requirements..."

# Combine all requirements
cat /dev/null > /tmp/all_requirements.txt
for file in $(find ../dashboard -name "requirements_actual.txt" -o -name "requirements.txt" -o -name "autowebserverrequirements.txt" | grep -v backup | grep -v utf8); do
    echo "  Reading $(basename $(dirname $file))/$(basename $file)"
    cat "$file" >> /tmp/all_requirements.txt
done

# Get unique packages (ignoring versions)
unique_count=$(cat /tmp/all_requirements.txt | grep -v "^#" | grep -v "^$" | cut -d'=' -f1 | cut -d'>' -f1 | cut -d'<' -f1 | sort -u | wc -l)
total_lines=$(cat /tmp/all_requirements.txt | grep -v "^#" | grep -v "^$" | wc -l)

echo ""
echo "Total requirement lines: $total_lines"
echo "Unique packages: $unique_count"
echo ""
echo "Top 20 most common packages:"
cat /tmp/all_requirements.txt | grep -v "^#" | grep -v "^$" | cut -d'=' -f1 | cut -d'>' -f1 | cut -d'<' -f1 | sort | uniq -c | sort -rn | head -20
