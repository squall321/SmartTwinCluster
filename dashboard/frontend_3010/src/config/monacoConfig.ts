/**
 * Monaco Editor Configuration
 *
 * Default editor options for all script editors
 */

import { editor } from 'monaco-editor';

export const DEFAULT_MONACO_OPTIONS: editor.IStandaloneEditorConstructionOptions = {
  theme: 'vs-dark',
  fontSize: 15,
  fontFamily: 'Menlo, Monaco, "Courier New", monospace',
  minimap: {
    enabled: true,
    side: 'right',
  },
  scrollBeyondLastLine: false,
  automaticLayout: true,
  wordWrap: 'on',
  lineNumbers: 'on',
  renderLineHighlight: 'all',
  folding: true,
  autoIndent: 'full',
  formatOnPaste: true,
  formatOnType: true,
  tabSize: 2,
  insertSpaces: true,
  bracketPairColorization: {
    enabled: true,
  },
  suggest: {
    showKeywords: true,
    showSnippets: true,
    showVariables: true,
    showFunctions: true,
  },
  quickSuggestions: {
    other: true,
    comments: false,
    strings: true,
  },
  suggestOnTriggerCharacters: true,
  acceptSuggestionOnCommitCharacter: true,
  acceptSuggestionOnEnter: 'on',
  tabCompletion: 'on',
};

/**
 * Light theme option
 */
export const LIGHT_MONACO_OPTIONS: editor.IStandaloneEditorConstructionOptions = {
  ...DEFAULT_MONACO_OPTIONS,
  theme: 'vs',
};

/**
 * Compact editor options (for smaller editors)
 */
export const COMPACT_MONACO_OPTIONS: editor.IStandaloneEditorConstructionOptions = {
  ...DEFAULT_MONACO_OPTIONS,
  fontSize: 12,
  minimap: {
    enabled: false,
  },
  lineNumbers: 'off',
  folding: false,
};
