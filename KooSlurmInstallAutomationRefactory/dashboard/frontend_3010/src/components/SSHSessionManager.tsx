import React, { useState, useEffect } from 'react';
import { Terminal, Plus, X, Play, RefreshCw, Clock, User, Server } from 'lucide-react';
import { API_CONFIG } from '../config/api.config';
import SSHTerminal from './SSHTerminal';

interface SSHSession {
  id: string;
  node_hostname: string;
  username: string;
  status: 'connected' | 'disconnected' | 'connecting';
  created_at: string;
  last_activity?: string;
  port?: number;
}

interface Node {
  name: string;
  state: string;
}

const SSHSessionManager: React.FC = () => {
  const [sessions, setSessions] = useState<SSHSession[]>([]);
  const [nodes, setNodes] = useState<Node[]>([]);
  const [loading, setLoading] = useState(false);
  const [showCreateModal, setShowCreateModal] = useState(false);
  const [selectedNode, setSelectedNode] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [selectedSession, setSelectedSession] = useState<SSHSession | null>(null);
  const [showConnectionModal, setShowConnectionModal] = useState(false);
  const [showTerminal, setShowTerminal] = useState(false);
  const [activeTerminalSession, setActiveTerminalSession] = useState<SSHSession | null>(null);

  // Get JWT token from localStorage
  const getToken = (): string | null => {
    return localStorage.getItem('jwt_token');
  };

  // Fetch available nodes
  const fetchNodes = async () => {
    try {
      const token = getToken();
      if (!token) {
        setError('Not authenticated');
        return;
      }

      const response = await fetch(`${API_CONFIG.API_BASE_URL}/api/ssh/nodes`, {
        headers: {
          'Authorization': `Bearer ${token}`,
        },
      });

      if (response.ok) {
        const data = await response.json();
        setNodes(data.nodes || []);
      } else {
        console.error('Failed to fetch nodes');
      }
    } catch (error) {
      console.error('Error fetching nodes:', error);
    }
  };

  // Fetch SSH sessions
  const fetchSessions = async () => {
    try {
      const token = getToken();
      if (!token) {
        setError('Not authenticated');
        return;
      }

      const response = await fetch(`${API_CONFIG.API_BASE_URL}/api/ssh/sessions`, {
        headers: {
          'Authorization': `Bearer ${token}`,
        },
      });

      if (response.ok) {
        const data = await response.json();
        setSessions(data.sessions || []);
        setError(null);
      } else {
        const errorData = await response.json();
        setError(errorData.error || 'Failed to fetch sessions');
      }
    } catch (error) {
      console.error('Error fetching sessions:', error);
      setError('Network error');
    }
  };

  // Create new SSH session
  const createSession = async () => {
    if (!selectedNode) {
      alert('Please select a node');
      return;
    }

    setLoading(true);
    try {
      const token = getToken();
      if (!token) {
        setError('Not authenticated');
        return;
      }

      const response = await fetch(`${API_CONFIG.API_BASE_URL}/api/ssh/sessions`, {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${token}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          node_hostname: selectedNode,
        }),
      });

      if (response.ok) {
        const data = await response.json();
        setShowCreateModal(false);
        setSelectedNode('');
        fetchSessions();
        setError(null);

        // Open terminal in new window/tab
        if (data.session && data.session.id) {
          // For now, just refresh sessions
          console.log('SSH session created:', data.session);
        }
      } else {
        const errorData = await response.json();
        setError(errorData.error || 'Failed to create session');
      }
    } catch (error) {
      console.error('Error creating session:', error);
      setError('Network error');
    } finally {
      setLoading(false);
    }
  };

  // Terminate SSH session
  const terminateSession = async (sessionId: string) => {
    if (!confirm('Are you sure you want to terminate this SSH session?')) {
      return;
    }

    try {
      const token = getToken();
      if (!token) {
        setError('Not authenticated');
        return;
      }

      const response = await fetch(`${API_CONFIG.API_BASE_URL}/api/ssh/sessions/${sessionId}`, {
        method: 'DELETE',
        headers: {
          'Authorization': `Bearer ${token}`,
        },
      });

      if (response.ok) {
        fetchSessions();
        setError(null);
      } else {
        const errorData = await response.json();
        setError(errorData.error || 'Failed to terminate session');
      }
    } catch (error) {
      console.error('Error terminating session:', error);
      setError('Network error');
    }
  };

  // Format timestamp
  const formatTimestamp = (timestamp: string): string => {
    const date = new Date(timestamp);
    return date.toLocaleString();
  };

  // Format time ago
  const formatTimeAgo = (timestamp: string): string => {
    const now = new Date();
    const past = new Date(timestamp);
    const diffMs = now.getTime() - past.getTime();
    const diffMins = Math.floor(diffMs / 60000);

    if (diffMins < 1) return 'Just now';
    if (diffMins < 60) return `${diffMins}m ago`;
    const diffHours = Math.floor(diffMins / 60);
    if (diffHours < 24) return `${diffHours}h ago`;
    const diffDays = Math.floor(diffHours / 24);
    return `${diffDays}d ago`;
  };

  // Initial load
  useEffect(() => {
    fetchNodes();
    fetchSessions();

    // Refresh sessions every 15 seconds
    const interval = setInterval(fetchSessions, 15000);
    return () => clearInterval(interval);
  }, []);

  return (
    <div className="p-6 space-y-6">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-3">
          <Terminal className="w-8 h-8 text-blue-600 dark:text-blue-400" />
          <div>
            <h1 className="text-2xl font-bold text-gray-900 dark:text-white">SSH Sessions</h1>
            <p className="text-sm text-gray-600 dark:text-gray-400">
              Manage SSH connections to cluster nodes
            </p>
          </div>
        </div>
        <div className="flex gap-2">
          <button
            onClick={fetchSessions}
            className="px-4 py-2 bg-gray-100 dark:bg-gray-700 text-gray-700 dark:text-gray-300 rounded-lg hover:bg-gray-200 dark:hover:bg-gray-600 transition-colors flex items-center gap-2"
          >
            <RefreshCw className="w-4 h-4" />
            Refresh
          </button>
          <button
            onClick={() => setShowCreateModal(true)}
            className="px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 transition-colors flex items-center gap-2"
          >
            <Plus className="w-4 h-4" />
            New Session
          </button>
        </div>
      </div>

      {/* Error Message */}
      {error && (
        <div className="bg-red-50 dark:bg-red-900/20 border border-red-200 dark:border-red-800 text-red-800 dark:text-red-200 px-4 py-3 rounded-lg">
          <p className="font-medium">Error</p>
          <p className="text-sm">{error}</p>
        </div>
      )}

      {/* Sessions Grid */}
      <div className="bg-white dark:bg-gray-800 rounded-lg border border-gray-200 dark:border-gray-700 overflow-hidden">
        <div className="px-6 py-4 border-b border-gray-200 dark:border-gray-700">
          <h2 className="text-lg font-semibold text-gray-900 dark:text-white">
            Active Sessions ({sessions.length})
          </h2>
        </div>

        {sessions.length === 0 ? (
          <div className="px-6 py-12 text-center">
            <Terminal className="w-16 h-16 mx-auto text-gray-300 dark:text-gray-600 mb-4" />
            <h3 className="text-lg font-medium text-gray-900 dark:text-white mb-2">
              No active SSH sessions
            </h3>
            <p className="text-gray-600 dark:text-gray-400 mb-4">
              Create a new SSH session to connect to a cluster node
            </p>
            <button
              onClick={() => setShowCreateModal(true)}
              className="px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 transition-colors inline-flex items-center gap-2"
            >
              <Plus className="w-4 h-4" />
              Create Session
            </button>
          </div>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full">
              <thead className="bg-gray-50 dark:bg-gray-900/50">
                <tr>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-400 uppercase tracking-wider">
                    Node
                  </th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-400 uppercase tracking-wider">
                    User
                  </th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-400 uppercase tracking-wider">
                    Status
                  </th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-400 uppercase tracking-wider">
                    Created
                  </th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-400 uppercase tracking-wider">
                    Last Activity
                  </th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-400 uppercase tracking-wider">
                    Actions
                  </th>
                </tr>
              </thead>
              <tbody className="bg-white dark:bg-gray-800 divide-y divide-gray-200 dark:divide-gray-700">
                {sessions.map((session) => (
                  <tr key={session.id} className="hover:bg-gray-50 dark:hover:bg-gray-700/50">
                    <td className="px-6 py-4 whitespace-nowrap">
                      <div className="flex items-center gap-2">
                        <Server className="w-4 h-4 text-gray-400" />
                        <span className="text-sm font-medium text-gray-900 dark:text-white">
                          {session.node_hostname}
                        </span>
                      </div>
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap">
                      <div className="flex items-center gap-2">
                        <User className="w-4 h-4 text-gray-400" />
                        <span className="text-sm text-gray-600 dark:text-gray-300">
                          {session.username}
                        </span>
                      </div>
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap">
                      <span
                        className={`px-2 py-1 text-xs font-medium rounded-full ${
                          session.status === 'connected'
                            ? 'bg-green-100 dark:bg-green-900/30 text-green-800 dark:text-green-200'
                            : session.status === 'connecting'
                            ? 'bg-yellow-100 dark:bg-yellow-900/30 text-yellow-800 dark:text-yellow-200'
                            : 'bg-gray-100 dark:bg-gray-700 text-gray-800 dark:text-gray-200'
                        }`}
                      >
                        {session.status}
                      </span>
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap">
                      <div className="flex items-center gap-2">
                        <Clock className="w-4 h-4 text-gray-400" />
                        <span className="text-sm text-gray-600 dark:text-gray-300">
                          {formatTimeAgo(session.created_at)}
                        </span>
                      </div>
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-600 dark:text-gray-300">
                      {session.last_activity ? formatTimeAgo(session.last_activity) : '-'}
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap text-sm">
                      <div className="flex items-center gap-2">
                        <button
                          onClick={() => {
                            setActiveTerminalSession(session);
                            setShowTerminal(true);
                            setShowConnectionModal(false);
                          }}
                          className="px-3 py-1 bg-blue-100 dark:bg-blue-900/30 text-blue-700 dark:text-blue-300 rounded hover:bg-blue-200 dark:hover:bg-blue-900/50 transition-colors flex items-center gap-1"
                          title="Open Terminal"
                        >
                          <Play className="w-3 h-3" />
                          Open
                        </button>
                        <button
                          onClick={() => terminateSession(session.id)}
                          className="px-3 py-1 bg-red-100 dark:bg-red-900/30 text-red-700 dark:text-red-300 rounded hover:bg-red-200 dark:hover:bg-red-900/50 transition-colors flex items-center gap-1"
                          title="Terminate Session"
                        >
                          <X className="w-3 h-3" />
                          End
                        </button>
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>

      {/* SSH Connection Info Modal */}
      {showConnectionModal && selectedSession && (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50">
          <div className="bg-white dark:bg-gray-800 rounded-lg shadow-xl w-full max-w-2xl mx-4">
            <div className="px-6 py-4 border-b border-gray-200 dark:border-gray-700 flex items-center justify-between">
              <h3 className="text-lg font-semibold text-gray-900 dark:text-white flex items-center gap-2">
                <Terminal className="w-5 h-5" />
                SSH Connection Information
              </h3>
              <button
                onClick={() => setShowConnectionModal(false)}
                className="text-gray-400 hover:text-gray-600 dark:hover:text-gray-200"
              >
                <X className="w-5 h-5" />
              </button>
            </div>

            <div className="px-6 py-4 space-y-4">
              <div className="bg-gray-50 dark:bg-gray-900/50 rounded-lg p-4">
                <div className="grid grid-cols-2 gap-4">
                  <div>
                    <label className="block text-sm font-medium text-gray-500 dark:text-gray-400 mb-1">
                      Node
                    </label>
                    <div className="text-base font-mono text-gray-900 dark:text-white">
                      {selectedSession.node_hostname}
                    </div>
                  </div>
                  <div>
                    <label className="block text-sm font-medium text-gray-500 dark:text-gray-400 mb-1">
                      User
                    </label>
                    <div className="text-base font-mono text-gray-900 dark:text-white">
                      {selectedSession.username}
                    </div>
                  </div>
                  <div>
                    <label className="block text-sm font-medium text-gray-500 dark:text-gray-400 mb-1">
                      Status
                    </label>
                    <span
                      className={`inline-block px-2 py-1 text-xs font-medium rounded-full ${
                        selectedSession.status === 'connected'
                          ? 'bg-green-100 dark:bg-green-900/30 text-green-800 dark:text-green-200'
                          : 'bg-gray-100 dark:bg-gray-700 text-gray-800 dark:text-gray-200'
                      }`}
                    >
                      {selectedSession.status}
                    </span>
                  </div>
                  <div>
                    <label className="block text-sm font-medium text-gray-500 dark:text-gray-400 mb-1">
                      Session ID
                    </label>
                    <div className="text-sm font-mono text-gray-900 dark:text-white truncate">
                      {selectedSession.id}
                    </div>
                  </div>
                </div>
              </div>

              <div className="bg-blue-50 dark:bg-blue-900/20 border border-blue-200 dark:border-blue-800 rounded-lg p-4">
                <h4 className="text-sm font-semibold text-blue-900 dark:text-blue-200 mb-2">
                  SSH Command
                </h4>
                <div className="bg-white dark:bg-gray-900 rounded px-4 py-3 font-mono text-sm text-gray-900 dark:text-white border border-blue-200 dark:border-blue-700">
                  ssh {selectedSession.username}@{selectedSession.node_hostname}
                </div>
                <p className="mt-2 text-xs text-blue-800 dark:text-blue-300">
                  Copy this command and run it in your terminal to connect to the SSH session.
                </p>
              </div>

              <div className="bg-amber-50 dark:bg-amber-900/20 border border-amber-200 dark:border-amber-800 rounded-lg p-4">
                <h4 className="text-sm font-semibold text-amber-900 dark:text-amber-200 mb-2">
                  Note
                </h4>
                <p className="text-sm text-amber-800 dark:text-amber-300">
                  Make sure your SSH key is configured on the target node. Web-based terminal
                  functionality (xterm.js) will be available in a future update.
                </p>
              </div>
            </div>

            <div className="px-6 py-4 border-t border-gray-200 dark:border-gray-700 flex justify-end">
              <button
                onClick={() => setShowConnectionModal(false)}
                className="px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 transition-colors"
              >
                Close
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Create Session Modal */}
      {showCreateModal && (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50">
          <div className="bg-white dark:bg-gray-800 rounded-lg shadow-xl w-full max-w-md mx-4">
            <div className="px-6 py-4 border-b border-gray-200 dark:border-gray-700 flex items-center justify-between">
              <h3 className="text-lg font-semibold text-gray-900 dark:text-white">
                Create SSH Session
              </h3>
              <button
                onClick={() => setShowCreateModal(false)}
                className="text-gray-400 hover:text-gray-600 dark:hover:text-gray-200"
              >
                <X className="w-5 h-5" />
              </button>
            </div>

            <div className="px-6 py-4 space-y-4">
              <div>
                <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
                  Select Node
                </label>
                <select
                  value={selectedNode}
                  onChange={(e) => setSelectedNode(e.target.value)}
                  className="w-full px-3 py-2 border border-gray-300 dark:border-gray-600 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent bg-white dark:bg-gray-700 text-gray-900 dark:text-white"
                >
                  <option value="">Choose a node...</option>
                  {nodes.map((node) => (
                    <option key={node.name} value={node.name}>
                      {node.name} ({node.state})
                    </option>
                  ))}
                </select>
              </div>

              <div className="bg-blue-50 dark:bg-blue-900/20 border border-blue-200 dark:border-blue-800 rounded-lg p-3">
                <p className="text-sm text-blue-800 dark:text-blue-200">
                  <strong>Note:</strong> SSH sessions use your existing SSH keys for authentication.
                  Make sure your SSH key is configured for the selected node.
                </p>
              </div>
            </div>

            <div className="px-6 py-4 border-t border-gray-200 dark:border-gray-700 flex justify-end gap-2">
              <button
                onClick={() => setShowCreateModal(false)}
                className="px-4 py-2 text-gray-700 dark:text-gray-300 hover:bg-gray-100 dark:hover:bg-gray-700 rounded-lg transition-colors"
              >
                Cancel
              </button>
              <button
                onClick={createSession}
                disabled={loading || !selectedNode}
                className="px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 disabled:bg-gray-400 disabled:cursor-not-allowed transition-colors flex items-center gap-2"
              >
                {loading ? (
                  <>
                    <RefreshCw className="w-4 h-4 animate-spin" />
                    Creating...
                  </>
                ) : (
                  <>
                    <Terminal className="w-4 h-4" />
                    Create Session
                  </>
                )}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Terminal Modal */}
      {showTerminal && activeTerminalSession && (
        <div className="fixed inset-0 bg-black/90 z-50 p-4">
          <div className="h-full max-w-6xl mx-auto flex flex-col">
            <SSHTerminal
              sessionId={activeTerminalSession.id}
              nodeHostname={activeTerminalSession.node_hostname}
              username={activeTerminalSession.username}
              onClose={() => {
                setShowTerminal(false);
                setActiveTerminalSession(null);
                fetchSessions();
              }}
            />
          </div>
        </div>
      )}
    </div>
  );
};

export default SSHSessionManager;
