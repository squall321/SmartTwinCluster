import { jsx as _jsx, jsxs as _jsxs } from "react/jsx-runtime";
import { useEffect, useState } from 'react';
import BaseLayout from '../layouts/BaseLayout';
import { Typography, message } from 'antd';
import FileTreeTextBox from '@components/common/FileTreeTextBox';
import FileFilterPanel from '@components/common/FileFilterPanel';
import FileTreeExplorer from '@components/common/FileTreeExplorer';
import { api } from '../api/axiosClient'; // ✅ axios 인스턴스 사용
const { Title } = Typography;
const ComponentTestAutomation = () => {
    const username = localStorage.getItem('username') || 'default_user';
    const [allDates, setAllDates] = useState([]);
    const [allModes, setAllModes] = useState([]);
    const [selectedDate, setSelectedDate] = useState();
    const [selectedMode, setSelectedMode] = useState();
    const [prefix, setPrefix] = useState('');
    const [submitted, setSubmitted] = useState(false);
    useEffect(() => {
        let cancelled = false;
        const load = async () => {
            try {
                // ✅ baseURL은 axiosClient에서 주입되므로 상대경로만 사용
                const { data } = await api.get(`/files/${encodeURIComponent(username)}`);
                if (cancelled || !data?.children)
                    return;
                // 날짜(최상위 디렉토리)
                const dates = data.children
                    .filter((entry) => entry.type === 'dir')
                    .map((entry) => entry.name)
                    .sort()
                    .reverse();
                setAllDates(dates);
                // 모드(각 날짜 하위 디렉토리)
                const modeSet = new Set();
                data.children.forEach((dateEntry) => {
                    dateEntry.children?.forEach((child) => {
                        if (child.type === 'dir')
                            modeSet.add(child.name);
                    });
                });
                setAllModes([...modeSet].sort());
            }
            catch (err) {
                if (cancelled)
                    return;
                console.error(err);
                message.error('날짜/모드 정보를 불러오지 못했습니다.');
            }
        };
        load();
        return () => {
            cancelled = true;
        };
    }, [username]); // ✅ username만 의존
    return (_jsx(BaseLayout, { isLoggedIn: true, children: _jsxs("div", { style: {
                padding: 24,
                width: '100%',
                backgroundColor: '#fff',
                minHeight: '100vh',
                borderRadius: '24px',
            }, children: [_jsx(Title, { level: 3, children: "\uD83E\uDD16 Component Test: Automation" }), _jsx(FileFilterPanel, { selectedDate: selectedDate, selectedMode: selectedMode, prefix: prefix, onDateChange: setSelectedDate, onModeChange: setSelectedMode, onPrefixChange: (val) => setPrefix(val || ''), onLoad: () => setSubmitted(true), allDates: allDates, allModes: allModes }), submitted && (_jsx(FileTreeTextBox, { username: username, date: selectedDate, mode: selectedMode, prefix: prefix || undefined })), _jsx(FileTreeExplorer, { username: username, prefix: prefix || undefined, allowDeleteDir: true })] }) }));
};
export default ComponentTestAutomation;
