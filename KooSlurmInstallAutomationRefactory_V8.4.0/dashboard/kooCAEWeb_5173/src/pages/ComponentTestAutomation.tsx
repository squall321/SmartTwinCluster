import React, { useEffect, useState } from 'react';
import BaseLayout from '../layouts/BaseLayout';
import { Typography, message } from 'antd';
import FileTreeTextBox from '@components/common/FileTreeTextBox';
import FileFilterPanel from '@components/common/FileFilterPanel';
import FileTreeExplorer from '@components/common/FileTreeExplorer';
import { api } from '../api/axiosClient'; // ✅ axios 인스턴스 사용

const { Title } = Typography;

type FileEntry = {
  name: string;
  type: 'file' | 'dir';
  children?: FileEntry[];
};

type FilesResponse = {
  children?: FileEntry[];
};

const ComponentTestAutomation: React.FC = () => {
  const username = localStorage.getItem('username') || 'default_user';
  const [allDates, setAllDates] = useState<string[]>([]);
  const [allModes, setAllModes] = useState<string[]>([]);

  const [selectedDate, setSelectedDate] = useState<string | undefined>();
  const [selectedMode, setSelectedMode] = useState<string | undefined>();
  const [prefix, setPrefix] = useState('');
  const [submitted, setSubmitted] = useState(false);

  useEffect(() => {
    let cancelled = false;

    const load = async () => {
      try {
        // ✅ baseURL은 axiosClient에서 주입되므로 상대경로만 사용
        const { data } = await api.get<FilesResponse>(`/files/${encodeURIComponent(username)}`);
        if (cancelled || !data?.children) return;

        // 날짜(최상위 디렉토리)
        const dates = data.children
          .filter((entry) => entry.type === 'dir')
          .map((entry) => entry.name)
          .sort()
          .reverse();
        setAllDates(dates);

        // 모드(각 날짜 하위 디렉토리)
        const modeSet = new Set<string>();
        data.children.forEach((dateEntry) => {
          dateEntry.children?.forEach((child) => {
            if (child.type === 'dir') modeSet.add(child.name);
          });
        });
        setAllModes([...modeSet].sort());
      } catch (err) {
        if (cancelled) return;
        console.error(err);
        message.error('날짜/모드 정보를 불러오지 못했습니다.');
      }
    };

    load();
    return () => {
      cancelled = true;
    };
  }, [username]); // ✅ username만 의존

  return (
    <BaseLayout isLoggedIn={true}>
      <div
        style={{
          padding: 24,
          width: '100%',
          backgroundColor: '#fff',
          minHeight: '100vh',
          borderRadius: '24px',
        }}
      >
        <Title level={3}>🤖 Component Test: Automation</Title>

        <FileFilterPanel
          selectedDate={selectedDate}
          selectedMode={selectedMode}
          prefix={prefix}
          onDateChange={setSelectedDate}
          onModeChange={setSelectedMode}
          onPrefixChange={(val) => setPrefix(val || '')}
          onLoad={() => setSubmitted(true)}
          allDates={allDates}
          allModes={allModes}
        />

        {submitted && (
          <FileTreeTextBox
            username={username}
            date={selectedDate}
            mode={selectedMode}
            prefix={prefix || undefined}
          />
        )}

        <FileTreeExplorer username={username} prefix={prefix || undefined} allowDeleteDir={true} />
      </div>
    </BaseLayout>
  );
};

export default ComponentTestAutomation;
