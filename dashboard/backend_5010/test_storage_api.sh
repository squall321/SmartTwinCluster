#!/bin/bash

# Storage API Backend Test Script

API_URL="http://localhost:5010/api"

echo "======================================"
echo "Storage API Backend Test"
echo "======================================"
echo ""

# Health check
echo "1. Health Check"
echo "GET $API_URL/health"
curl -s "$API_URL/health" | python3 -m json.tool
echo ""
echo ""

# Storage stats
echo "2. Shared Storage Stats"
echo "GET $API_URL/storage/data/stats"
curl -s "$API_URL/storage/data/stats" | python3 -m json.tool
echo ""
echo ""

# Datasets
echo "3. Datasets List"
echo "GET $API_URL/storage/data/datasets"
curl -s "$API_URL/storage/data/datasets" | python3 -m json.tool
echo ""
echo ""

# Scratch nodes
echo "4. Scratch Nodes"
echo "GET $API_URL/storage/scratch/nodes"
curl -s "$API_URL/storage/scratch/nodes" | python3 -m json.tool
echo ""
echo ""

# File list test (will return empty in mock mode)
echo "5. List Files"
echo "GET $API_URL/storage/files?path=/Data&type=data"
curl -s "$API_URL/storage/files?path=/Data&type=data" | python3 -m json.tool
echo ""
echo ""

echo "======================================"
echo "Test Complete!"
echo "======================================"
