#!/bin/bash

# Database Reset Script
# This script deletes the existing database and reinitializes it with LS-DYNA templates only

echo "=========================================="
echo "Database Reset Script"
echo "=========================================="
echo ""

cd "$(dirname "$0")/backend_5010"

# Check if database exists
if [ -f "database/dashboard.db" ]; then
    echo "🗑️  Found existing database: database/dashboard.db"
    rm -f database/dashboard.db
    echo "✅ Deleted old database"
else
    echo "ℹ️  No existing database found"
fi

echo ""
echo "🔄 Reinitializing database..."
python3 init_db.py

echo ""
echo "=========================================="
echo "✅ Database reset complete!"
echo "=========================================="
echo ""
echo "Production mode will now show only LS-DYNA templates (2)"
echo ""
