/**
 * SaveTemplateModal Component
 *
 * Modal for saving current job configuration as a template
 */

import React, { useState } from 'react';
import {
  Dialog,
  DialogTitle,
  DialogContent,
  DialogActions,
  Button,
  TextField,
  Box,
  FormControlLabel,
  Switch,
  Select,
  MenuItem,
  FormControl,
  InputLabel,
  Alert,
} from '@mui/material';
import { Save as SaveIcon } from '@mui/icons-material';

interface SaveTemplateModalProps {
  open: boolean;
  onClose: () => void;
  onSave: (templateData: SaveTemplateData) => Promise<void>;
  defaultName?: string;
}

export interface SaveTemplateData {
  name: string;
  description: string;
  category: 'simulation' | 'ml' | 'data' | 'custom';
  shared: boolean;
}

const SaveTemplateModal: React.FC<SaveTemplateModalProps> = ({
  open,
  onClose,
  onSave,
  defaultName = '',
}) => {
  const [name, setName] = useState(defaultName);
  const [description, setDescription] = useState('');
  const [category, setCategory] = useState<'simulation' | 'ml' | 'data' | 'custom'>('simulation');
  const [shared, setShared] = useState(false);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const handleSave = async () => {
    // Validation
    if (!name.trim()) {
      setError('템플릿 이름을 입력해주세요');
      return;
    }

    if (name.length < 3) {
      setError('템플릿 이름은 최소 3자 이상이어야 합니다');
      return;
    }

    setSaving(true);
    setError(null);

    try {
      await onSave({
        name: name.trim(),
        description: description.trim(),
        category,
        shared,
      });

      // Reset form
      setName('');
      setDescription('');
      setCategory('simulation');
      setShared(false);
      onClose();
    } catch (err) {
      setError(err instanceof Error ? err.message : '템플릿 저장에 실패했습니다');
    } finally {
      setSaving(false);
    }
  };

  const handleClose = () => {
    if (!saving) {
      setName('');
      setDescription('');
      setError(null);
      onClose();
    }
  };

  return (
    <Dialog open={open} onClose={handleClose} maxWidth="sm" fullWidth>
      <DialogTitle>템플릿으로 저장</DialogTitle>

      <DialogContent>
        <Box sx={{ pt: 2 }}>
          {error && (
            <Alert severity="error" sx={{ mb: 2 }}>
              {error}
            </Alert>
          )}

          <TextField
            autoFocus
            fullWidth
            label="템플릿 이름"
            value={name}
            onChange={(e) => setName(e.target.value)}
            placeholder="예: 대규모 LS-DYNA 시뮬레이션 (64코어)"
            required
            sx={{ mb: 2 }}
            helperText="나중에 쉽게 찾을 수 있도록 명확한 이름을 입력하세요"
          />

          <TextField
            fullWidth
            label="설명"
            value={description}
            onChange={(e) => setDescription(e.target.value)}
            placeholder="이 템플릿의 용도를 설명해주세요"
            multiline
            rows={3}
            sx={{ mb: 2 }}
            helperText="선택사항: 템플릿 사용 시기나 용도를 간단히 설명"
          />

          <FormControl fullWidth sx={{ mb: 2 }}>
            <InputLabel>카테고리</InputLabel>
            <Select
              value={category}
              label="카테고리"
              onChange={(e) => setCategory(e.target.value as any)}
            >
              <MenuItem value="simulation">시뮬레이션</MenuItem>
              <MenuItem value="ml">머신러닝</MenuItem>
              <MenuItem value="data">데이터 처리</MenuItem>
              <MenuItem value="custom">사용자 정의</MenuItem>
            </Select>
          </FormControl>

          <FormControlLabel
            control={
              <Switch
                checked={shared}
                onChange={(e) => setShared(e.target.checked)}
              />
            }
            label="팀원과 공유"
          />

          <Box sx={{ mt: 1, ml: 4 }}>
            <small style={{ color: '#666' }}>
              {shared
                ? '이 템플릿을 모든 팀원이 사용할 수 있습니다'
                : '이 템플릿은 나만 사용할 수 있습니다'}
            </small>
          </Box>
        </Box>
      </DialogContent>

      <DialogActions>
        <Button onClick={handleClose} disabled={saving}>
          취소
        </Button>
        <Button
          onClick={handleSave}
          variant="contained"
          disabled={saving || !name.trim()}
          startIcon={<SaveIcon />}
        >
          {saving ? '저장 중...' : '저장'}
        </Button>
      </DialogActions>
    </Dialog>
  );
};

export default SaveTemplateModal;
