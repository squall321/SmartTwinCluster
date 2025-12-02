import React, { useEffect, useRef } from 'react';
import { Terminal } from 'xterm';
import { FitAddon } from 'xterm-addon-fit';
import { WebLinksAddon } from 'xterm-addon-web-links';
import { io, Socket } from 'socket.io-client';
import 'xterm/css/xterm.css';

interface SSHTerminalProps {
  sessionId: string;
  nodeHostname: string;
  username: string;
  onClose: () => void;
}

const SSHTerminal: React.FC<SSHTerminalProps> = ({ sessionId, nodeHostname, username, onClose }) => {
  const terminalRef = useRef<HTMLDivElement>(null);
  const xtermRef = useRef<Terminal | null>(null);
  const fitAddonRef = useRef<FitAddon | null>(null);
  const socketRef = useRef<Socket | null>(null);

  useEffect(() => {
    if (!terminalRef.current) return;

    // Create terminal instance
    const terminal = new Terminal({
      cursorBlink: true,
      fontSize: 14,
      fontFamily: 'Menlo, Monaco, "Courier New", monospace',
      theme: {
        background: '#1e1e1e',
        foreground: '#d4d4d4',
        cursor: '#ffffff',
        selectionBackground: '#264f78',
        black: '#000000',
        red: '#cd3131',
        green: '#0dbc79',
        yellow: '#e5e510',
        blue: '#2472c8',
        magenta: '#bc3fbc',
        cyan: '#11a8cd',
        white: '#e5e5e5',
        brightBlack: '#666666',
        brightRed: '#f14c4c',
        brightGreen: '#23d18b',
        brightYellow: '#f5f543',
        brightBlue: '#3b8eea',
        brightMagenta: '#d670d6',
        brightCyan: '#29b8db',
        brightWhite: '#e5e5e5',
      },
      rows: 30,
      cols: 100,
    });

    const fitAddon = new FitAddon();
    const webLinksAddon = new WebLinksAddon();

    terminal.loadAddon(fitAddon);
    terminal.loadAddon(webLinksAddon);

    terminal.open(terminalRef.current);
    fitAddon.fit();

    xtermRef.current = terminal;
    fitAddonRef.current = fitAddon;

    // Handle window resize
    const handleResize = () => {
      fitAddon.fit();
    };
    window.addEventListener('resize', handleResize);

    // Get JWT token
    const token = localStorage.getItem('jwt_token');

    // Establish SocketIO connection for SSH I/O
    const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
    const host = window.location.host;

    terminal.writeln(`\x1b[1;32mConnecting to ${username}@${nodeHostname}...\x1b[0m`);
    terminal.writeln('');

    try {
      // Create SocketIO connection
      // Connect to the /ssh-ws namespace
      const socket = io(`${protocol}//${host}/ssh-ws`, {
        path: '/socket.io',
        transports: ['websocket', 'polling'],
        auth: {
          token: token
        }
      });

      socketRef.current = socket;

      socket.on('connect', () => {
        terminal.writeln('\x1b[1;32mWebSocket connected!\x1b[0m');
        terminal.writeln('');

        // Start SSH session
        socket.emit('start_session', {
          session_id: sessionId,
          node_hostname: nodeHostname,
          username: username,
          rows: terminal.rows,
          cols: terminal.cols
        });
      });

      socket.on('connected', (data) => {
        terminal.writeln(`\x1b[1;32m${data.message}\x1b[0m`);
        terminal.writeln('');
      });

      socket.on('output', (data) => {
        terminal.write(data.data);
      });

      socket.on('error', (data) => {
        terminal.writeln(`\r\n\x1b[1;31mError: ${data.message}\x1b[0m`);
      });

      socket.on('status', (data) => {
        terminal.writeln(`\x1b[36m${data.message}\x1b[0m`);
      });

      socket.on('disconnected', (data) => {
        terminal.writeln(`\r\n\x1b[1;33m${data.message}\x1b[0m`);
        terminal.writeln('\x1b[2mConnection closed.\x1b[0m');
      });

      socket.on('disconnect', () => {
        terminal.writeln('\r\n\x1b[1;33mSocket disconnected.\x1b[0m');
      });

      socket.on('connect_error', (error) => {
        console.error('SocketIO connection error:', error);
        terminal.writeln('\r\n\x1b[1;31mConnection error. Please check your network.\x1b[0m');
      });

      // Handle terminal input
      terminal.onData((data) => {
        if (socket.connected) {
          socket.emit('input', {
            session_id: sessionId,
            data: data
          });
        }
      });

      // Handle terminal resize
      terminal.onResize(({ cols, rows }) => {
        fitAddon.fit();
        if (socket.connected) {
          socket.emit('resize', {
            session_id: sessionId,
            cols,
            rows
          });
        }
      });

    } catch (error) {
      console.error('Failed to establish SocketIO connection:', error);
      terminal.writeln('\x1b[1;31mFailed to connect to SSH session.\x1b[0m');
      terminal.writeln('\x1b[2mThis feature requires WebSocket support.\x1b[0m');
    }

    // Cleanup
    return () => {
      window.removeEventListener('resize', handleResize);
      if (socketRef.current) {
        socketRef.current.disconnect();
      }
      terminal.dispose();
    };
  }, [sessionId, nodeHostname, username]);

  return (
    <div className="flex flex-col h-full bg-gray-900">
      {/* Terminal Header */}
      <div className="flex items-center justify-between px-4 py-2 bg-gray-800 border-b border-gray-700">
        <div className="flex items-center gap-2">
          <div className="flex gap-1.5">
            <button
              onClick={onClose}
              className="w-3 h-3 rounded-full bg-red-500 hover:bg-red-600 transition-colors"
              title="Close"
            />
            <div className="w-3 h-3 rounded-full bg-yellow-500" />
            <div className="w-3 h-3 rounded-full bg-green-500" />
          </div>
          <span className="text-sm text-gray-300 ml-2 font-mono">
            {username}@{nodeHostname}
          </span>
        </div>
        <div className="text-xs text-gray-500">
          Session: {sessionId.substring(0, 8)}
        </div>
      </div>

      {/* Terminal Content */}
      <div
        ref={terminalRef}
        className="flex-1 p-2 overflow-hidden"
        style={{ minHeight: '400px' }}
      />

      {/* Terminal Footer */}
      <div className="px-4 py-2 bg-gray-800 border-t border-gray-700 text-xs text-gray-500">
        Press <kbd className="px-1 py-0.5 bg-gray-700 rounded">Ctrl+C</kbd> to interrupt • <kbd className="px-1 py-0.5 bg-gray-700 rounded">Ctrl+D</kbd> to exit
      </div>
    </div>
  );
};

export default SSHTerminal;
