import { jsxs as _jsxs, jsx as _jsx } from "react/jsx-runtime";
import { useEffect, useState } from 'react';
import { Select, Spin, Typography } from 'antd';
import { api } from '../api/axiosClient';
import { parseMaterialTxt } from '../components/MaterialParserWorker'; // ✅ 기존 유틸 함수 활용
const { Option } = Select;
const { Title } = Typography;
const MaterialSelectorComponent = ({ onChange, mode = 'display' }) => {
    const [loading, setLoading] = useState(true);
    const [materialOptions, setMaterialOptions] = useState([]);
    const [materialDict, setMaterialDict] = useState({});
    const [selected, setSelected] = useState(null);
    useEffect(() => {
        const fetchMaterial = async () => {
            setLoading(true);
            try {
                let url;
                if (mode === 'display') {
                    url = `/api/materials/display`;
                }
                else {
                    const listRes = await api.post(`/api/materials/all`);
                    const fileList = listRes.data.files;
                    const displayFile = fileList.find((f) => f.name === 'DisplayMaterial.txt');
                    url = displayFile ? `${displayFile.url}` : `${fileList[0].url}`;
                }
                const res = await api.get(url, { responseType: 'text' });
                const parsed = parseMaterialTxt(res.data); // ✅ 여기서 가져다 씀
                setMaterialDict(parsed);
                setMaterialOptions(Object.keys(parsed));
            }
            catch (err) {
                console.error('📛 Material fetch 실패:', err);
            }
            finally {
                setLoading(false);
            }
        };
        fetchMaterial();
    }, [mode]);
    const handleChange = (value) => {
        setSelected(value);
        if (onChange && materialDict[value]) {
            onChange(value, materialDict[value]);
        }
    };
    return (_jsxs("div", { style: {
            padding: 24,
            backgroundColor: '#fff',
            minHeight: '100vh',
            borderRadius: '24px',
        }, children: [_jsxs(Title, { level: 4, children: ["\uD83E\uDDFE \uC7AC\uB8CC \uC120\uD0DD (", mode === 'display' ? 'DisplayMaterial.txt' : 'All', ")"] }), loading ? (_jsx(Spin, {})) : (_jsx(Select, { style: { width: 400 }, showSearch: true, placeholder: "Material \uC774\uB984 \uC120\uD0DD", onChange: handleChange, value: selected ?? undefined, children: materialOptions.map((name) => (_jsx(Option, { value: name, children: name }, name))) }))] }));
};
export default MaterialSelectorComponent;
