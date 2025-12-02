import { jsx as _jsx, jsxs as _jsxs } from "react/jsx-runtime";
/**
 * SaveTemplateModal Component
 *
 * Modal for saving current job configuration as a template
 */
import { useState } from 'react';
import { Dialog, DialogTitle, DialogContent, DialogActions, Button, TextField, Box, FormControlLabel, Switch, Select, MenuItem, FormControl, InputLabel, Alert, } from '@mui/material';
import { Save as SaveIcon } from '@mui/icons-material';
const SaveTemplateModal = ({ open, onClose, onSave, defaultName = '', }) => {
    const [name, setName] = useState(defaultName);
    const [description, setDescription] = useState('');
    const [category, setCategory] = useState('simulation');
    const [shared, setShared] = useState(false);
    const [saving, setSaving] = useState(false);
    const [error, setError] = useState(null);
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
        }
        catch (err) {
            setError(err instanceof Error ? err.message : '템플릿 저장에 실패했습니다');
        }
        finally {
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
    return (_jsxs(Dialog, { open: open, onClose: handleClose, maxWidth: "sm", fullWidth: true, children: [_jsx(DialogTitle, { children: "\uD15C\uD50C\uB9BF\uC73C\uB85C \uC800\uC7A5" }), _jsx(DialogContent, { children: _jsxs(Box, { sx: { pt: 2 }, children: [error && (_jsx(Alert, { severity: "error", sx: { mb: 2 }, children: error })), _jsx(TextField, { autoFocus: true, fullWidth: true, label: "\uD15C\uD50C\uB9BF \uC774\uB984", value: name, onChange: (e) => setName(e.target.value), placeholder: "\uC608: \uB300\uADDC\uBAA8 LS-DYNA \uC2DC\uBBAC\uB808\uC774\uC158 (64\uCF54\uC5B4)", required: true, sx: { mb: 2 }, helperText: "\uB098\uC911\uC5D0 \uC27D\uAC8C \uCC3E\uC744 \uC218 \uC788\uB3C4\uB85D \uBA85\uD655\uD55C \uC774\uB984\uC744 \uC785\uB825\uD558\uC138\uC694" }), _jsx(TextField, { fullWidth: true, label: "\uC124\uBA85", value: description, onChange: (e) => setDescription(e.target.value), placeholder: "\uC774 \uD15C\uD50C\uB9BF\uC758 \uC6A9\uB3C4\uB97C \uC124\uBA85\uD574\uC8FC\uC138\uC694", multiline: true, rows: 3, sx: { mb: 2 }, helperText: "\uC120\uD0DD\uC0AC\uD56D: \uD15C\uD50C\uB9BF \uC0AC\uC6A9 \uC2DC\uAE30\uB098 \uC6A9\uB3C4\uB97C \uAC04\uB2E8\uD788 \uC124\uBA85" }), _jsxs(FormControl, { fullWidth: true, sx: { mb: 2 }, children: [_jsx(InputLabel, { children: "\uCE74\uD14C\uACE0\uB9AC" }), _jsxs(Select, { value: category, label: "\uCE74\uD14C\uACE0\uB9AC", onChange: (e) => setCategory(e.target.value), children: [_jsx(MenuItem, { value: "simulation", children: "\uC2DC\uBBAC\uB808\uC774\uC158" }), _jsx(MenuItem, { value: "ml", children: "\uBA38\uC2E0\uB7EC\uB2DD" }), _jsx(MenuItem, { value: "data", children: "\uB370\uC774\uD130 \uCC98\uB9AC" }), _jsx(MenuItem, { value: "custom", children: "\uC0AC\uC6A9\uC790 \uC815\uC758" })] })] }), _jsx(FormControlLabel, { control: _jsx(Switch, { checked: shared, onChange: (e) => setShared(e.target.checked) }), label: "\uD300\uC6D0\uACFC \uACF5\uC720" }), _jsx(Box, { sx: { mt: 1, ml: 4 }, children: _jsx("small", { style: { color: '#666' }, children: shared
                                    ? '이 템플릿을 모든 팀원이 사용할 수 있습니다'
                                    : '이 템플릿은 나만 사용할 수 있습니다' }) })] }) }), _jsxs(DialogActions, { children: [_jsx(Button, { onClick: handleClose, disabled: saving, children: "\uCDE8\uC18C" }), _jsx(Button, { onClick: handleSave, variant: "contained", disabled: saving || !name.trim(), startIcon: _jsx(SaveIcon, {}), children: saving ? '저장 중...' : '저장' })] })] }));
};
export default SaveTemplateModal;
