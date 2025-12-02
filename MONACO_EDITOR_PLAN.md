# Monaco Editor 통합 계획

**목표**: TemplateEditor의 스크립트 편집에 Monaco Editor 적용 + 동적 자동완성

**예상 소요 시간**: 1-2시간

---

## 📊 구현 개요

### 현재 상태
```tsx
<textarea
  value={mainExecScript}
  onChange={(e) => setMainExecScript(e.target.value)}
  rows={12}
  className="w-full px-3 py-2 border rounded-lg font-mono text-sm"
/>
```

### 목표 상태
```tsx
<ScriptEditor
  value={mainExecScript}
  onChange={setMainExecScript}
  language="bash"
  height="400px"
  completionItems={dynamicCompletionItems}  // 동적 자동완성
/>
```

---

## 🎯 Phase 1: 설치 및 기본 설정

### 1.1 패키지 설치

```bash
cd dashboard/frontend_3010

# Monaco Editor React wrapper
npm install @monaco-editor/react

# (Monaco Editor 자체는 peer dependency로 자동 설치됨)
```

**패키지 정보**:
- `@monaco-editor/react`: React용 Monaco Editor wrapper
- 번들 크기: ~3MB (gzipped)
- TypeScript 지원: 내장

---

### 1.2 기본 설정 파일 생성

**파일**: `src/utils/monacoConfig.ts`

```typescript
import * as monaco from 'monaco-editor';

/**
 * Monaco Editor 전역 설정
 */
export function configureMonaco() {
  // Bash 언어 설정
  monaco.languages.register({ id: 'bash' });

  // 기본 테마 설정
  monaco.editor.defineTheme('script-editor-dark', {
    base: 'vs-dark',
    inherit: true,
    rules: [],
    colors: {
      'editor.background': '#1e1e1e',
      'editor.foreground': '#d4d4d4',
    },
  });

  monaco.editor.defineTheme('script-editor-light', {
    base: 'vs',
    inherit: true,
    rules: [],
    colors: {
      'editor.background': '#ffffff',
      'editor.foreground': '#000000',
    },
  });
}

/**
 * Monaco Editor 기본 옵션
 */
export const defaultEditorOptions: monaco.editor.IStandaloneEditorConstructionOptions = {
  fontSize: 13,
  fontFamily: "'Fira Code', 'Courier New', monospace",
  lineNumbers: 'on',
  minimap: { enabled: false },  // 미니맵 비활성화 (공간 절약)
  scrollBeyondLastLine: false,
  wordWrap: 'on',
  automaticLayout: true,
  tabSize: 2,
  insertSpaces: true,
  quickSuggestions: {
    other: true,
    comments: false,
    strings: true,
  },
  suggestOnTriggerCharacters: true,
  acceptSuggestionOnEnter: 'on',
  suggest: {
    showKeywords: true,
    showSnippets: true,
    showWords: true,
  },
};
```

---

## 🎯 Phase 2: ScriptEditor 컴포넌트 생성

### 2.1 기본 컴포넌트

**파일**: `src/components/ScriptEditor/ScriptEditor.tsx`

```typescript
import React, { useRef, useEffect } from 'react';
import Editor, { OnMount } from '@monaco-editor/react';
import * as monaco from 'monaco-editor';
import { defaultEditorOptions } from '../../utils/monacoConfig';

export interface CompletionItem {
  label: string;
  kind: 'variable' | 'function' | 'snippet' | 'keyword';
  insertText: string;
  documentation?: string;
  detail?: string;
}

interface ScriptEditorProps {
  value: string;
  onChange: (value: string) => void;
  height?: string;
  language?: string;
  theme?: 'light' | 'dark';
  completionItems?: CompletionItem[];
  readOnly?: boolean;
  placeholder?: string;
}

export const ScriptEditor: React.FC<ScriptEditorProps> = ({
  value,
  onChange,
  height = '400px',
  language = 'bash',
  theme = 'light',
  completionItems = [],
  readOnly = false,
  placeholder,
}) => {
  const editorRef = useRef<monaco.editor.IStandaloneCodeEditor | null>(null);
  const completionProviderRef = useRef<monaco.IDisposable | null>(null);

  // Editor 마운트 핸들러
  const handleEditorDidMount: OnMount = (editor, monaco) => {
    editorRef.current = editor;

    // Placeholder 표시 (값이 비어있을 때)
    if (!value && placeholder) {
      editor.updateOptions({
        // @ts-ignore
        placeholder,
      });
    }

    // 자동완성 Provider 등록
    registerCompletionProvider(monaco, language, completionItems);
  };

  // 자동완성 Provider 등록 함수
  const registerCompletionProvider = (
    monaco: typeof import('monaco-editor'),
    language: string,
    items: CompletionItem[]
  ) => {
    // 기존 Provider 제거
    if (completionProviderRef.current) {
      completionProviderRef.current.dispose();
    }

    // 새 Provider 등록
    completionProviderRef.current = monaco.languages.registerCompletionItemProvider(
      language,
      {
        provideCompletionItems: (model, position) => {
          const word = model.getWordUntilPosition(position);
          const range = {
            startLineNumber: position.lineNumber,
            endLineNumber: position.lineNumber,
            startColumn: word.startColumn,
            endColumn: word.endColumn,
          };

          const suggestions = items.map((item) => ({
            label: item.label,
            kind: getCompletionItemKind(monaco, item.kind),
            insertText: item.insertText,
            insertTextRules: item.insertText.includes('${')
              ? monaco.languages.CompletionItemInsertTextRule.InsertAsSnippet
              : undefined,
            documentation: item.documentation,
            detail: item.detail,
            range,
          }));

          return { suggestions };
        },
      }
    );
  };

  // CompletionItemKind 매핑
  const getCompletionItemKind = (
    monaco: typeof import('monaco-editor'),
    kind: CompletionItem['kind']
  ): monaco.languages.CompletionItemKind => {
    switch (kind) {
      case 'variable':
        return monaco.languages.CompletionItemKind.Variable;
      case 'function':
        return monaco.languages.CompletionItemKind.Function;
      case 'snippet':
        return monaco.languages.CompletionItemKind.Snippet;
      case 'keyword':
        return monaco.languages.CompletionItemKind.Keyword;
      default:
        return monaco.languages.CompletionItemKind.Text;
    }
  };

  // completionItems 변경 시 Provider 재등록
  useEffect(() => {
    if (editorRef.current) {
      const monacoInstance = (window as any).monaco;
      if (monacoInstance) {
        registerCompletionProvider(monacoInstance, language, completionItems);
      }
    }
  }, [completionItems, language]);

  // Cleanup
  useEffect(() => {
    return () => {
      if (completionProviderRef.current) {
        completionProviderRef.current.dispose();
      }
    };
  }, []);

  return (
    <div className="border border-gray-300 rounded-lg overflow-hidden">
      <Editor
        height={height}
        language={language}
        value={value}
        onChange={(value) => onChange(value || '')}
        onMount={handleEditorDidMount}
        theme={theme === 'dark' ? 'script-editor-dark' : 'script-editor-light'}
        options={{
          ...defaultEditorOptions,
          readOnly,
        }}
      />
    </div>
  );
};

export default ScriptEditor;
```

---

## 🎯 Phase 3: 동적 자동완성 Provider 구현

### 3.1 자동완성 아이템 생성 유틸리티

**파일**: `src/utils/scriptCompletionItems.ts`

```typescript
import { CompletionItem } from '../components/ScriptEditor/ScriptEditor';

/**
 * Slurm 환경변수 자동완성 (고정)
 */
export const SLURM_VARIABLES: CompletionItem[] = [
  {
    label: 'SLURM_JOB_ID',
    kind: 'variable',
    insertText: '$SLURM_JOB_ID',
    documentation: 'Job ID assigned by Slurm',
    detail: 'Slurm Variable',
  },
  {
    label: 'SLURM_JOB_NAME',
    kind: 'variable',
    insertText: '$SLURM_JOB_NAME',
    documentation: 'Job name',
    detail: 'Slurm Variable',
  },
  {
    label: 'SLURM_SUBMIT_DIR',
    kind: 'variable',
    insertText: '$SLURM_SUBMIT_DIR',
    documentation: 'Directory from which sbatch was invoked',
    detail: 'Slurm Variable',
  },
  {
    label: 'SLURM_NODELIST',
    kind: 'variable',
    insertText: '$SLURM_NODELIST',
    documentation: 'List of nodes allocated to the job',
    detail: 'Slurm Variable',
  },
  {
    label: 'SLURM_NTASKS',
    kind: 'variable',
    insertText: '$SLURM_NTASKS',
    documentation: 'Number of tasks',
    detail: 'Slurm Variable',
  },
  {
    label: 'SLURM_CPUS_PER_TASK',
    kind: 'variable',
    insertText: '$SLURM_CPUS_PER_TASK',
    documentation: 'Number of CPUs per task',
    detail: 'Slurm Variable',
  },
  {
    label: 'SLURM_ARRAY_TASK_ID',
    kind: 'variable',
    insertText: '$SLURM_ARRAY_TASK_ID',
    documentation: 'Task ID for array jobs',
    detail: 'Slurm Variable',
  },
];

/**
 * JOB_* 변수 생성 (Slurm Config 기반)
 */
export function generateJobVariables(slurmConfig: {
  partition: string;
  nodes: number;
  ntasks: number;
  cpus_per_task: number;
  mem: string;
  time: string;
}): CompletionItem[] {
  return [
    {
      label: 'JOB_PARTITION',
      kind: 'variable',
      insertText: '$JOB_PARTITION',
      documentation: `Partition: ${slurmConfig.partition}`,
      detail: `Auto-injected: "${slurmConfig.partition}"`,
    },
    {
      label: 'JOB_NODES',
      kind: 'variable',
      insertText: '$JOB_NODES',
      documentation: `Number of nodes: ${slurmConfig.nodes}`,
      detail: `Auto-injected: ${slurmConfig.nodes}`,
    },
    {
      label: 'JOB_NTASKS',
      kind: 'variable',
      insertText: '$JOB_NTASKS',
      documentation: `Number of tasks: ${slurmConfig.ntasks}`,
      detail: `Auto-injected: ${slurmConfig.ntasks}`,
    },
    {
      label: 'JOB_CPUS_PER_TASK',
      kind: 'variable',
      insertText: '$JOB_CPUS_PER_TASK',
      documentation: `CPUs per task: ${slurmConfig.cpus_per_task}`,
      detail: `Auto-injected: ${slurmConfig.cpus_per_task}`,
    },
    {
      label: 'JOB_MEMORY',
      kind: 'variable',
      insertText: '$JOB_MEMORY',
      documentation: `Memory: ${slurmConfig.mem}`,
      detail: `Auto-injected: "${slurmConfig.mem}"`,
    },
    {
      label: 'JOB_TIME',
      kind: 'variable',
      insertText: '$JOB_TIME',
      documentation: `Time limit: ${slurmConfig.time}`,
      detail: `Auto-injected: "${slurmConfig.time}"`,
    },
  ];
}

/**
 * FILE_* 변수 생성 (requiredFiles, optionalFiles 기반)
 */
export function generateFileVariables(
  requiredFiles: any[],
  optionalFiles: any[]
): CompletionItem[] {
  const allFiles = [...requiredFiles, ...optionalFiles];

  return allFiles.flatMap((file) => {
    const varName = `FILE_${file.file_key.toUpperCase()}`;
    const items: CompletionItem[] = [
      {
        label: varName,
        kind: 'variable',
        insertText: `$${varName}`,
        documentation: file.description || file.name,
        detail: `File: ${file.pattern} (${file.required ? 'required' : 'optional'})`,
      },
    ];

    // 복수 파일 가능성 체크
    if (
      file.pattern.includes('*') ||
      file.description?.includes('들') ||
      file.description?.includes('multiple')
    ) {
      items.push({
        label: `${varName}_COUNT`,
        kind: 'variable',
        insertText: `$${varName}_COUNT`,
        documentation: `Number of ${file.name || file.pattern} files uploaded`,
        detail: 'File count variable',
      });
    }

    return items;
  });
}

/**
 * 디렉토리 변수 (고정)
 */
export const DIRECTORY_VARIABLES: CompletionItem[] = [
  {
    label: 'WORK_DIR',
    kind: 'variable',
    insertText: '$WORK_DIR',
    documentation: 'Working directory',
    detail: 'Auto-injected: $SLURM_SUBMIT_DIR',
  },
  {
    label: 'RESULT_DIR',
    kind: 'variable',
    insertText: '$RESULT_DIR',
    documentation: 'Results output directory',
    detail: 'Auto-injected: $WORK_DIR/results',
  },
];

/**
 * Apptainer 명령어 스니펫 (고정)
 */
export const APPTAINER_SNIPPETS: CompletionItem[] = [
  {
    label: 'apptainer exec',
    kind: 'snippet',
    insertText: 'apptainer exec ${1:$APPTAINER_IMAGE} ${2:command}',
    documentation: 'Execute a command inside an Apptainer container',
    detail: 'Apptainer snippet',
  },
  {
    label: 'apptainer exec with bind',
    kind: 'snippet',
    insertText: [
      'apptainer exec \\',
      '  --bind ${1:/shared} \\',
      '  ${2:$APPTAINER_IMAGE} \\',
      '  ${3:command}',
    ].join('\n'),
    documentation: 'Execute with bind mount',
    detail: 'Apptainer snippet',
  },
  {
    label: 'mpirun apptainer',
    kind: 'snippet',
    insertText: 'mpirun -np ${1:$SLURM_NTASKS} apptainer exec ${2:$APPTAINER_IMAGE} ${3:command}',
    documentation: 'Run MPI job with Apptainer',
    detail: 'MPI + Apptainer snippet',
  },
];

/**
 * Bash 기본 명령어 (선택적)
 */
export const BASH_COMMANDS: CompletionItem[] = [
  {
    label: 'export',
    kind: 'keyword',
    insertText: 'export ${1:VAR}="${2:value}"',
    documentation: 'Export environment variable',
  },
  {
    label: 'echo',
    kind: 'keyword',
    insertText: 'echo "${1:message}"',
    documentation: 'Print message',
  },
  {
    label: 'mkdir',
    kind: 'keyword',
    insertText: 'mkdir -p ${1:directory}',
    documentation: 'Create directory',
  },
  {
    label: 'cd',
    kind: 'keyword',
    insertText: 'cd ${1:directory}',
    documentation: 'Change directory',
  },
];

/**
 * 모든 자동완성 아이템 통합
 */
export function generateAllCompletionItems(
  slurmConfig: {
    partition: string;
    nodes: number;
    ntasks: number;
    cpus_per_task: number;
    mem: string;
    time: string;
  },
  requiredFiles: any[],
  optionalFiles: any[]
): CompletionItem[] {
  return [
    ...SLURM_VARIABLES,
    ...generateJobVariables(slurmConfig),
    ...generateFileVariables(requiredFiles, optionalFiles),
    ...DIRECTORY_VARIABLES,
    ...APPTAINER_SNIPPETS,
    ...BASH_COMMANDS,
  ];
}
```

---

## 🎯 Phase 4: TemplateEditor에 통합

### 4.1 TemplateEditor 수정

**파일**: `src/components/TemplateManagement/TemplateEditor.tsx`

```typescript
import { ScriptEditor } from '../ScriptEditor/ScriptEditor';
import { generateAllCompletionItems } from '../../utils/scriptCompletionItems';

// ... 기존 코드 ...

export const TemplateEditor: React.FC<TemplateEditorProps> = ({
  template,
  onClose,
  onSave
}) => {
  // ... 기존 state ...

  // Monaco Editor 테마 설정
  const [editorTheme, setEditorTheme] = useState<'light' | 'dark'>('light');

  // 동적 자동완성 아이템 생성
  const completionItems = useMemo(() => {
    return generateAllCompletionItems(
      {
        partition,
        nodes,
        ntasks,
        cpus_per_task: cpusPerTask,
        mem: memory,
        time,
      },
      requiredFiles,
      optionalFiles
    );
  }, [partition, nodes, ntasks, cpusPerTask, memory, time, requiredFiles, optionalFiles]);

  // ... 기존 코드 ...

  return (
    // ... 기존 JSX ...

    {/* Script Tab */}
    {activeTab === 'script' && (
      <div className="space-y-6">
        {/* 테마 토글 버튼 (선택적) */}
        <div className="flex justify-end">
          <button
            onClick={() => setEditorTheme(editorTheme === 'light' ? 'dark' : 'light')}
            className="text-xs px-3 py-1 border rounded"
          >
            {editorTheme === 'light' ? '🌙 Dark' : '☀️ Light'}
          </button>
        </div>

        {/* Variable Guide Panel (기존 유지) */}
        <div className="bg-blue-50 border border-blue-200 rounded-lg p-4">
          {/* ... 기존 변수 가이드 ... */}
        </div>

        {/* Pre-execution Script */}
        <div>
          <div className="flex items-center justify-between mb-1">
            <label className="block text-sm font-medium text-gray-700">
              Pre-execution Script
              <span className="text-xs text-gray-500 ml-2">(Setup, create directories, etc.)</span>
            </label>
            <button
              type="button"
              onClick={() => setPreExecScript(generatePreExecWithVariables())}
              className="text-xs px-2 py-1 bg-blue-100 text-blue-700 hover:bg-blue-200 rounded flex items-center gap-1"
            >
              <RefreshCw className="w-3 h-3" />
              Refresh Variables
            </button>
          </div>

          <ScriptEditor
            value={preExecScript}
            onChange={setPreExecScript}
            height="300px"
            language="bash"
            theme={editorTheme}
            completionItems={completionItems}
            placeholder="#!/bin/bash\necho 'Starting job...'\nmkdir -p output"
          />
        </div>

        {/* Main Execution Script */}
        <div>
          <div className="flex items-center justify-between mb-1">
            <label className="block text-sm font-medium text-gray-700">
              Main Execution Script *
              <span className="text-xs text-gray-500 ml-2">(Core computation)</span>
            </label>

            {/* Command Template Inserter Button (기존 유지) */}
            {selectedApptainerImage && selectedApptainerImage.command_templates && selectedApptainerImage.command_templates.length > 0 && (
              <button
                type="button"
                onClick={() => setShowTemplateInserter(true)}
                className="text-xs px-3 py-1.5 bg-gradient-to-r from-purple-600 to-blue-600 text-white hover:from-purple-700 hover:to-blue-700 rounded flex items-center gap-1.5 shadow-sm"
              >
                <Sparkles className="w-3.5 h-3.5" />
                Insert Command Template
              </button>
            )}
          </div>

          {/* Info message (기존 유지) */}
          {selectedApptainerImage && selectedApptainerImage.command_templates && selectedApptainerImage.command_templates.length > 0 && (
            <div className="mb-2 p-2 bg-purple-50 border border-purple-200 rounded text-xs text-purple-700">
              <strong>{selectedApptainerImage.command_templates.length}</strong> command template{selectedApptainerImage.command_templates.length !== 1 ? 's' : ''} available from <strong>{selectedApptainerImage.name}</strong>. Click "Insert Command Template" to use them.
            </div>
          )}

          <ScriptEditor
            value={mainExecScript}
            onChange={setMainExecScript}
            height="500px"
            language="bash"
            theme={editorTheme}
            completionItems={completionItems}
            placeholder="#!/bin/bash\napptainer exec $APPTAINER_IMAGE python3 simulation.py"
          />
        </div>

        {/* Post-execution Script */}
        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">
            Post-execution Script
            <span className="text-xs text-gray-500 ml-2">(Cleanup, collect results, etc.)</span>
          </label>

          <ScriptEditor
            value={postExecScript}
            onChange={setPostExecScript}
            height="300px"
            language="bash"
            theme={editorTheme}
            completionItems={completionItems}
            placeholder="#!/bin/bash\necho 'Job completed'\ncp output/* /shared/results/"
          />
        </div>

        {/* 자동완성 가이드 (선택적) */}
        <div className="p-4 bg-gray-50 border border-gray-200 rounded-lg">
          <h4 className="text-sm font-semibold text-gray-900 mb-2">💡 Autocomplete Guide</h4>
          <div className="text-xs text-gray-700 space-y-1">
            <div>• Press <kbd className="px-1.5 py-0.5 bg-white border rounded">Ctrl+Space</kbd> to trigger autocomplete</div>
            <div>• Type <code className="bg-white px-1 py-0.5 rounded">$</code> to see available variables</div>
            <div>• Type <code className="bg-white px-1 py-0.5 rounded">apptainer</code> to see Apptainer snippets</div>
            <div>• Available: Slurm variables, JOB_* variables, FILE_* variables, Apptainer commands</div>
          </div>
        </div>
      </div>
    )}

    // ... 기존 코드 ...
  );
};
```

---

## 🎯 Phase 5: Export 및 정리

### 5.1 Index 파일

**파일**: `src/components/ScriptEditor/index.ts`

```typescript
export { ScriptEditor } from './ScriptEditor';
export type { CompletionItem } from './ScriptEditor';
```

---

## 📊 구현 체크리스트

### Phase 1: 설치 및 설정 (10분)
- [ ] `@monaco-editor/react` 설치
- [ ] `monacoConfig.ts` 생성
- [ ] 테마 설정

### Phase 2: ScriptEditor 컴포넌트 (30분)
- [ ] `ScriptEditor.tsx` 생성
- [ ] 기본 Props 정의
- [ ] Editor 마운트 핸들러
- [ ] 자동완성 Provider 등록 로직

### Phase 3: 자동완성 아이템 (20분)
- [ ] `scriptCompletionItems.ts` 생성
- [ ] Slurm 변수 정의
- [ ] JOB_* 변수 생성 함수
- [ ] FILE_* 변수 생성 함수
- [ ] Apptainer 스니펫 정의
- [ ] 통합 함수 작성

### Phase 4: TemplateEditor 통합 (20분)
- [ ] ScriptEditor import
- [ ] completionItems useMemo
- [ ] textarea → ScriptEditor 교체 (3곳)
- [ ] 테마 토글 추가 (선택적)
- [ ] 자동완성 가이드 추가 (선택적)

### Phase 5: 테스트 및 문서화 (20분)
- [ ] Frontend 빌드 테스트
- [ ] 자동완성 동작 확인
- [ ] 스니펫 동작 확인
- [ ] 문서 업데이트

**총 예상 시간**: 1시간 40분

---

## 🎨 사용자 경험 개선 사항

### Before (기존 textarea)
```
┌─────────────────────────────────────────┐
│ Main Execution Script *                 │
│ ┌─────────────────────────────────────┐ │
│ │#!/bin/bash                     ↕ 12 │ │
│ │                                lines │ │
│ │apptainer exec $APPT...              │ │  ← 스크롤 필요
│ │                                      │ │
│ └─────────────────────────────────────┘ │
└─────────────────────────────────────────┘
```

### After (Monaco Editor)
```
┌───────────────────────────────────────────────────┐
│ Main Execution Script *        [☀️ Light] [✨ Insert]│
├───────────────────────────────────────────────────┤
│  1  #!/bin/bash                                   │
│  2                                                │
│  3  # Autocomplete available:                     │
│  4  apptainer exec $APPTAINER_IMAGE \             │
│  5      python3 $FILE_PYTHON_SCRIPT \      ← 자동완성│
│  6      --cores $JOB_NTA█                         │
│       ┌─────────────────────────────┐             │
│       │ 💡 Suggestions:              │             │
│       │ ✓ JOB_NTASKS (4)            │             │
│       │   JOB_NODES (1)             │             │
│       │   SLURM_NTASKS              │             │
│       └─────────────────────────────┘             │
│  7      --memory $JOB_MEMORY                      │
│  8                                                │
│  9  echo "Job completed"                          │
│ 10                                          ↕ 500px│
└───────────────────────────────────────────────────┘

💡 Autocomplete Guide
• Ctrl+Space to trigger • $ for variables • apptainer for snippets
```

---

## 🚀 추가 개선 가능 사항 (선택적)

### 1. Syntax Validation
```typescript
// 간단한 Bash 문법 검증
monaco.languages.registerDocumentSemanticTokensProvider('bash', {
  // ...
});
```

### 2. 코드 포맷팅
```typescript
// Prettier 통합
editor.getAction('editor.action.formatDocument').run();
```

### 3. 단축키 커스터마이징
```typescript
editor.addCommand(monaco.KeyMod.CtrlCmd | monaco.KeyCode.KEY_S, () => {
  handleSave();
});
```

### 4. 변수 하이라이팅
```typescript
// $VAR_NAME 하이라이팅
monaco.languages.setMonarchTokensProvider('bash', {
  tokenizer: {
    root: [
      [/\$[A-Z_]+/, 'variable'],
    ],
  },
});
```

---

## 📈 예상 효과

### 개발자 경험 개선
- ✅ 자동완성으로 변수명 오타 방지
- ✅ 문법 하이라이팅으로 가독성 향상
- ✅ 라인 넘버로 디버깅 용이
- ✅ Snippet으로 반복 작업 감소

### 사용자 경험 개선
- ✅ 전문적인 코드 편집 환경
- ✅ 실시간 자동완성 제안
- ✅ 큰 화면 (500px)으로 편집 편의
- ✅ 다크 모드 지원

---

## 🎯 다음 단계

이 계획대로 구현하시겠습니까?

1. **즉시 시작**: Phase 1부터 순차적으로 구현
2. **부분 구현**: ScriptEditor만 먼저 구현 후 테스트
3. **수정 요청**: 계획 수정 또는 추가 기능 제안

어떻게 진행하시겠습니까?
