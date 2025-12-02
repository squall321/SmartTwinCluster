/**
 * ScriptEditor Component
 *
 * Monaco Editor wrapper with dynamic autocomplete support
 */

import React, { useRef, useEffect, useState } from 'react';
import Editor, { Monaco, OnMount } from '@monaco-editor/react';
import { editor, languages } from 'monaco-editor';
import { DEFAULT_MONACO_OPTIONS } from '../../config/monacoConfig';
import { CompletionItem, toMonacoCompletionItem } from '../../utils/scriptCompletionItems';

export interface ScriptEditorProps {
  value: string;
  onChange: (value: string) => void;
  height?: string;
  language?: string;
  theme?: 'vs-dark' | 'vs' | 'hc-black';
  options?: editor.IStandaloneEditorConstructionOptions;
  completionItems?: CompletionItem[];
  placeholder?: string;
  className?: string;
}

/**
 * ScriptEditor Component
 *
 * Features:
 * - Monaco Editor integration
 * - Dynamic autocomplete based on completionItems prop
 * - Bash syntax highlighting
 * - Line numbers, folding, minimap
 */
export const ScriptEditor: React.FC<ScriptEditorProps> = ({
  value,
  onChange,
  height = '500px',
  language = 'shell',
  theme = 'vs-dark',
  options,
  completionItems = [],
  placeholder,
  className = '',
}) => {
  const editorRef = useRef<editor.IStandaloneCodeEditor | null>(null);
  const monacoRef = useRef<Monaco | null>(null);
  const disposableRef = useRef<any | null>(null);
  const [isEditorReady, setIsEditorReady] = useState(false);

  /**
   * Register completion provider when completionItems change
   */
  useEffect(() => {
    if (!isEditorReady || !monacoRef.current) return;

    // Dispose previous provider
    if (disposableRef.current) {
      disposableRef.current.dispose();
    }

    // Register new provider
    disposableRef.current = registerCompletionProvider(
      monacoRef.current,
      language,
      completionItems
    );

    return () => {
      if (disposableRef.current) {
        disposableRef.current.dispose();
      }
    };
  }, [completionItems, isEditorReady, language]);

  /**
   * Register completion provider
   */
  const registerCompletionProvider = (
    monaco: Monaco,
    lang: string,
    items: CompletionItem[]
  ) => {
    return monaco.languages.registerCompletionItemProvider(lang, {
      provideCompletionItems: (model, position) => {
        const word = model.getWordUntilPosition(position);
        const range = {
          startLineNumber: position.lineNumber,
          endLineNumber: position.lineNumber,
          startColumn: word.startColumn,
          endColumn: word.endColumn,
        };

        // Get text before cursor to check for $ trigger
        const textUntilPosition = model.getValueInRange({
          startLineNumber: position.lineNumber,
          startColumn: 1,
          endLineNumber: position.lineNumber,
          endColumn: position.column,
        });

        // If user typed $, show variable suggestions first
        const showVariablesFirst = textUntilPosition.charAt(textUntilPosition.length - 1) === '$';

        let suggestions = items.map((item) =>
          toMonacoCompletionItem(item, range)
        );

        // Sort: variables first if $ was typed
        if (showVariablesFirst) {
          suggestions = suggestions.sort((a, b) => {
            const aIsVar =
              a.kind === languages.CompletionItemKind.Variable;
            const bIsVar =
              b.kind === languages.CompletionItemKind.Variable;
            if (aIsVar && !bIsVar) return -1;
            if (!aIsVar && bIsVar) return 1;
            return 0;
          });
        }

        return {
          suggestions,
        };
      },
      triggerCharacters: ['$', '_', '.'],
    });
  };

  /**
   * Handle editor mount
   */
  const handleEditorDidMount: OnMount = (editor, monaco) => {
    editorRef.current = editor;
    monacoRef.current = monaco;
    setIsEditorReady(true);

    // Set placeholder if empty
    if (!value && placeholder) {
      editor.setValue(placeholder);
      editor.setSelection({
        startLineNumber: 1,
        startColumn: 1,
        endLineNumber: editor.getModel()?.getLineCount() || 1,
        endColumn: editor.getModel()?.getLineMaxColumn(1) || 1,
      });
    }

    // Focus on editor
    editor.focus();
  };

  /**
   * Handle value change
   */
  const handleChange = (newValue: string | undefined) => {
    onChange(newValue || '');
  };

  /**
   * Merge options
   */
  const mergedOptions: editor.IStandaloneEditorConstructionOptions = {
    ...DEFAULT_MONACO_OPTIONS,
    theme,
    ...options,
  };

  return (
    <div className={`border border-gray-300 rounded-lg overflow-hidden ${className}`}>
      <Editor
        height={height}
        language={language}
        value={value}
        onChange={handleChange}
        onMount={handleEditorDidMount}
        options={mergedOptions}
        theme={theme}
      />
    </div>
  );
};

export default ScriptEditor;
