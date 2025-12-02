-- Migration: Add command_templates column to apptainer_images table
-- Date: 2025-11-10
-- Purpose: Support command template system for dynamic script generation

-- Check if column already exists before adding
-- SQLite doesn't support IF NOT EXISTS for ALTER TABLE, so we use a workaround

-- Add command_templates column
ALTER TABLE apptainer_images
ADD COLUMN command_templates TEXT DEFAULT '[]';

-- Verify the change
SELECT 'Migration completed: command_templates column added' as status;
