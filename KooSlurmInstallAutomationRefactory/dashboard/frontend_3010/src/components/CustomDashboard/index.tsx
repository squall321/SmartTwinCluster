import React, { useState, useEffect } from 'react';
import GridLayout from 'react-grid-layout';
import type { Layout } from 'react-grid-layout';
import { Plus, Save, RotateCcw, Settings } from 'lucide-react';
import WidgetLibrary from './WidgetLibrary';
import { WidgetType, widgetRegistry } from './widgetRegistry';
import 'react-grid-layout/css/styles.css';
import 'react-resizable/css/styles.css';

interface WidgetInstance {
  i: string;
  type: WidgetType;
  x: number;
  y: number;
  w: number;
  h: number;
}

interface CustomDashboardProps {
  mode: 'mock' | 'production';
}

const CustomDashboard: React.FC<CustomDashboardProps> = ({ mode }) => {
  const [widgets, setWidgets] = useState<WidgetInstance[]>([]);
  const [layout, setLayout] = useState<Layout[]>([]);
  const [showLibrary, setShowLibrary] = useState(false);
  const [isEditMode, setIsEditMode] = useState(true);

  // Load layout from localStorage
  useEffect(() => {
    const savedLayout = localStorage.getItem('customDashboardLayout');
    if (savedLayout) {
      try {
        const parsed = JSON.parse(savedLayout);
        setWidgets(parsed.widgets || []);
        setLayout(parsed.layout || []);
      } catch (e) {
        console.error('Failed to load dashboard layout:', e);
        loadDefaultLayout();
      }
    } else {
      // Default layout
      loadDefaultLayout();
    }
  }, []);

  const loadDefaultLayout = () => {
    const defaultWidgets: WidgetInstance[] = [
      { i: 'cpu-1', type: 'cpu', x: 0, y: 0, w: 6, h: 2 },
      { i: 'memory-1', type: 'memory', x: 6, y: 0, w: 6, h: 2 },
      { i: 'gpu-1', type: 'gpu', x: 0, y: 2, w: 6, h: 2 },
      { i: 'jobqueue-1', type: 'jobQueue', x: 6, y: 2, w: 6, h: 2 },
      { i: 'recentjobs-1', type: 'recentJobs', x: 0, y: 4, w: 12, h: 3 },
    ];
    setWidgets(defaultWidgets);
    setLayout(defaultWidgets.map(w => ({ i: w.i, x: w.x, y: w.y, w: w.w, h: w.h })));
  };

  const saveLayout = () => {
    const layoutData = {
      widgets,
      layout,
      savedAt: new Date().toISOString()
    };
    localStorage.setItem('customDashboardLayout', JSON.stringify(layoutData));
    alert('✅ Dashboard layout saved successfully!');
  };

  const resetLayout = () => {
    if (window.confirm('Reset to default layout?')) {
      loadDefaultLayout();
      localStorage.removeItem('customDashboardLayout');
    }
  };

  const addWidget = (type: WidgetType) => {
    const id = `${type}-${Date.now()}`;
    const newWidget: WidgetInstance = {
      i: id,
      type,
      x: 0,
      y: Infinity, // Place at bottom
      w: 6,
      h: 2
    };
    setWidgets([...widgets, newWidget]);
    setLayout([...layout, { i: id, x: 0, y: Infinity, w: 6, h: 2 }]);
    setShowLibrary(false);
  };

  const removeWidget = (id: string) => {
    setWidgets(widgets.filter(w => w.i !== id));
    setLayout(layout.filter(l => l.i !== id));
  };

  const onLayoutChange = (newLayout: Layout[]) => {
    setLayout(newLayout);
    // Update widgets with new positions
    const updatedWidgets = widgets.map(widget => {
      const layoutItem = newLayout.find(l => l.i === widget.i);
      if (layoutItem) {
        return { ...widget, x: layoutItem.x, y: layoutItem.y, w: layoutItem.w, h: layoutItem.h };
      }
      return widget;
    });
    setWidgets(updatedWidgets);
  };

  return (
    <div className="h-full flex flex-col bg-gray-50 dark:bg-gray-900">
      {/* Header */}
      <div className="bg-white dark:bg-gray-800 border-b border-gray-200 dark:border-gray-700 px-6 py-4">
        <div className="flex items-center justify-between">
          <div>
            <h1 className="text-2xl font-bold text-gray-900 dark:text-white">
              Custom Dashboard
            </h1>
            <p className="text-sm text-gray-500 dark:text-gray-400 mt-1">
              Freely arrange and resize widgets
              {mode === 'mock' && <span className="ml-2 text-amber-600">🎭 Mock Mode</span>}
            </p>
          </div>
          
          <div className="flex items-center gap-3">
            <button
              onClick={() => setIsEditMode(!isEditMode)}
              className={`px-4 py-2 rounded-lg font-medium transition-colors ${
                isEditMode
                  ? 'bg-blue-500 text-white hover:bg-blue-600'
                  : 'bg-gray-200 text-gray-700 hover:bg-gray-300 dark:bg-gray-700 dark:text-gray-300'
              }`}
            >
              <Settings className="w-4 h-4 inline mr-2" />
              {isEditMode ? 'Edit Mode' : 'View Mode'}
            </button>
            
            <button
              onClick={() => setShowLibrary(true)}
              className="px-4 py-2 bg-green-500 text-white rounded-lg hover:bg-green-600 font-medium transition-colors"
            >
              <Plus className="w-4 h-4 inline mr-2" />
              Add Widget
            </button>
            
            <button
              onClick={saveLayout}
              className="px-4 py-2 bg-blue-500 text-white rounded-lg hover:bg-blue-600 font-medium transition-colors"
            >
              <Save className="w-4 h-4 inline mr-2" />
              Save
            </button>
            
            <button
              onClick={resetLayout}
              className="px-4 py-2 bg-gray-500 text-white rounded-lg hover:bg-gray-600 font-medium transition-colors"
            >
              <RotateCcw className="w-4 h-4 inline mr-2" />
              Reset
            </button>
          </div>
        </div>
      </div>

      {/* Grid Layout */}
      <div className="flex-1 overflow-auto p-6">
        {widgets.length === 0 ? (
          <div className="flex items-center justify-center h-full">
            <div className="text-center">
              <div className="text-6xl mb-4">📊</div>
              <h3 className="text-xl font-semibold text-gray-700 dark:text-gray-300 mb-2">
                No Widgets
              </h3>
              <p className="text-gray-500 dark:text-gray-400 mb-4">
                Click 'Add Widget' button to configure your dashboard
              </p>
              <button
                onClick={() => setShowLibrary(true)}
                className="px-6 py-3 bg-blue-500 text-white rounded-lg hover:bg-blue-600 font-medium transition-colors"
              >
                <Plus className="w-5 h-5 inline mr-2" />
                Add Widget
              </button>
            </div>
          </div>
        ) : (
          <GridLayout
            className="layout"
            layout={layout}
            cols={12}
            rowHeight={100}
            width={1200}
            isDraggable={isEditMode}
            isResizable={isEditMode}
            onLayoutChange={onLayoutChange}
            draggableHandle=".drag-handle"
          >
            {widgets.map(widget => {
              const WidgetComponent = widgetRegistry[widget.type];
              return (
                <div key={widget.i} className="bg-white dark:bg-gray-800 rounded-lg shadow-md overflow-hidden">
                  {WidgetComponent && (
                    <WidgetComponent
                      id={widget.i}
                      onRemove={() => removeWidget(widget.i)}
                      isEditMode={isEditMode}
                      mode={mode}
                    />
                  )}
                </div>
              );
            })}
          </GridLayout>
        )}
      </div>

      {/* Widget Library Modal */}
      {showLibrary && (
        <WidgetLibrary
          onClose={() => setShowLibrary(false)}
          onAddWidget={addWidget}
        />
      )}
    </div>
  );
};

export default CustomDashboard;
