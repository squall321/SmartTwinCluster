import { jsxs as _jsxs, jsx as _jsx } from "react/jsx-runtime";
import { useEffect, useState } from 'react';
import { Select, Spin, Typography } from 'antd';
import { useMaterialCache } from './MaterialCacheContext';
const { Option } = Select;
const { Title } = Typography;
const MaterialSelectorComponent = ({ onChange, mode = 'display' }) => {
    const [loading, setLoading] = useState(true);
    const [materialOptions, setMaterialOptions] = useState([]);
    const [materialDict, setMaterialDict] = useState({});
    const [selected, setSelected] = useState(null);
    const { getMaterials } = useMaterialCache();
    useEffect(() => {
        const loadMaterials = async () => {
            setLoading(true);
            const parsed = await getMaterials(mode);
            setMaterialDict(parsed);
            setMaterialOptions(Object.keys(parsed));
            setLoading(false);
        };
        loadMaterials();
    }, [mode]);
    const handleChange = (value) => {
        setSelected(value);
        if (onChange && materialDict[value]) {
            onChange(value, materialDict[value]);
        }
    };
    return (_jsxs("div", { style: { padding: '1.5rem' }, children: [_jsxs(Title, { level: 4, children: ["\uD83E\uDDFE \uC7AC\uB8CC \uC120\uD0DD (", mode, ")"] }), loading ? (_jsx(Spin, {})) : (_jsx(Select, { style: { width: 600 }, showSearch: true, placeholder: "Material \uC120\uD0DD (Type / Name / MID)", onChange: handleChange, value: selected ?? undefined, filterOption: (input, option) => {
                    const val = option?.value || '';
                    const data = materialDict[val];
                    return (data?.name?.toLowerCase().includes(input.toLowerCase()) ||
                        data?.type?.toLowerCase().includes(input.toLowerCase()) ||
                        data?.id?.trim().includes(input));
                }, children: materialOptions.map((key) => {
                    const mat = materialDict[key];
                    return (_jsxs(Option, { value: key, children: [mat.type, " / ", mat.name, " (MID=", mat.id.trim(), ")"] }, key));
                }) }))] }));
};
export default MaterialSelectorComponent;
