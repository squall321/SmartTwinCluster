import React, { useState, useEffect } from 'react';
import { Star, GripVertical, X, Plus, Trash2 } from 'lucide-react';
import { WidgetProps } from '../widgetRegistry';

interface Favorite {
  id: string;
  name: string;
  type: 'job' | 'script' | 'template' | 'node';
  icon: string;
}

const FavoritesWidget: React.FC<WidgetProps> = ({ id, onRemove, isEditMode, mode }) => {
  const [favorites, setFavorites] = useState<Favorite[]>([]);

  useEffect(() => {
    loadFavorites();
  }, []);

  const loadFavorites = () => {
    const saved = localStorage.getItem('dashboard_favorites');
    if (saved) {
      try {
        setFavorites(JSON.parse(saved));
      } catch (e) {
        console.error('Failed to load favorites:', e);
      }
    } else {
      // Default favorites
      setFavorites([
        { id: '1', name: 'Training Script', type: 'script', icon: '📝' },
        { id: '2', name: 'ML Template', type: 'template', icon: '🤖' },
        { id: '3', name: 'GPU Node 01', type: 'node', icon: '🖥️' },
        { id: '4', name: 'Data Pipeline', type: 'job', icon: '⚙️' },
      ]);
    }
  };

  const saveFavorites = (newFavorites: Favorite[]) => {
    localStorage.setItem('dashboard_favorites', JSON.stringify(newFavorites));
    setFavorites(newFavorites);
  };

  const removeFavorite = (favoriteId: string) => {
    const newFavorites = favorites.filter(f => f.id !== favoriteId);
    saveFavorites(newFavorites);
  };

  const handleFavoriteClick = (favorite: Favorite) => {
    alert(`${favorite.name} feature is under development.`);
  };

  const getTypeColor = (type: string) => {
    const colors = {
      job: 'bg-blue-100 text-blue-700 dark:bg-blue-900/30 dark:text-blue-400',
      script: 'bg-purple-100 text-purple-700 dark:bg-purple-900/30 dark:text-purple-400',
      template: 'bg-green-100 text-green-700 dark:bg-green-900/30 dark:text-green-400',
      node: 'bg-orange-100 text-orange-700 dark:bg-orange-900/30 dark:text-orange-400',
    };
    return colors[type as keyof typeof colors] || colors.job;
  };

  return (
    <div className="h-full flex flex-col">
      {/* Header */}
      <div className="flex items-center justify-between px-4 py-3 border-b border-gray-200 dark:border-gray-700">
        <div className="flex items-center gap-2">
          {isEditMode && (
            <div className="drag-handle cursor-move">
              <GripVertical className="w-4 h-4 text-gray-400" />
            </div>
          )}
          <Star className="w-5 h-5 text-yellow-500" />
          <h3 className="font-semibold text-gray-900 dark:text-white">Favorites</h3>
        </div>
        <div className="flex items-center gap-2">
          <button
            onClick={() => alert('Add favorites feature is under development.')}
            className="p-1 hover:bg-gray-100 dark:hover:bg-gray-700 rounded transition-colors"
          >
            <Plus className="w-4 h-4 text-gray-500 dark:text-gray-400" />
          </button>
          {isEditMode && (
            <button
              onClick={onRemove}
              className="p-1 hover:bg-gray-100 dark:hover:bg-gray-700 rounded transition-colors"
            >
              <X className="w-4 h-4 text-gray-400" />
            </button>
          )}
        </div>
      </div>

      {/* Content */}
      <div className="flex-1 overflow-y-auto p-4">
        {favorites.length === 0 ? (
          <div className="flex flex-col items-center justify-center h-full text-center">
            <Star className="w-12 h-12 text-gray-300 dark:text-gray-600 mb-3" />
            <p className="text-gray-500 dark:text-gray-400 mb-2">No Favorites</p>
            <button
              onClick={() => alert('Add favorites feature is under development.')}
              className="text-sm text-blue-500 hover:text-blue-600 dark:text-blue-400 dark:hover:text-blue-300"
            >
              + Add Favorite
            </button>
          </div>
        ) : (
          <div className="grid grid-cols-2 gap-3">
            {favorites.map(favorite => (
              <div
                key={favorite.id}
                className="group bg-gray-50 dark:bg-gray-700/50 rounded-lg p-3 hover:bg-gray-100 dark:hover:bg-gray-700 transition-colors cursor-pointer relative"
                onClick={() => handleFavoriteClick(favorite)}
              >
                <div className="flex items-start justify-between mb-2">
                  <div className="text-2xl">{favorite.icon}</div>
                  {isEditMode && (
                    <button
                      onClick={(e) => {
                        e.stopPropagation();
                        removeFavorite(favorite.id);
                      }}
                      className="opacity-0 group-hover:opacity-100 p-1 hover:bg-red-100 dark:hover:bg-red-900/30 rounded transition-all"
                    >
                      <Trash2 className="w-3 h-3 text-red-500" />
                    </button>
                  )}
                </div>
                <h4 className="font-medium text-sm text-gray-900 dark:text-white mb-1 truncate">
                  {favorite.name}
                </h4>
                <span className={`inline-block px-2 py-0.5 rounded text-xs font-medium ${getTypeColor(favorite.type)}`}>
                  {favorite.type}
                </span>
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  );
};

export default FavoritesWidget;
