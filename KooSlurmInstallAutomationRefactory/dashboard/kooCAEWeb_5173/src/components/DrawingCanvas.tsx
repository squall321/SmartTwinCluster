// DrawingCanvas.tsx
import React, { useState, useRef, useImperativeHandle, forwardRef } from 'react';
import { Stage, Layer, Line, Rect, Circle } from 'react-konva';
import GLBLayer from '../components/GLBLayer';

type Point = { x: number; y: number };

type Shape =
  | {
      id: number;
      type: 'poly';
      points: Point[];
      modelPoints?: Point[];
    }
  | {
      id: number;
      type: 'box';
      canvasRect: { x: number; y: number; width: number; height: number };
      modelRect?: { x: number; y: number; width: number; height: number };

    };

interface DrawingCanvasProps {
  glbUrl?: string;
  glbFile?: File;
  onModelBounds?: (bounds: { xmin: number; xmax: number; ymin: number; ymax: number }) => void;
}

const DrawingCanvas = forwardRef<any, DrawingCanvasProps>(({ glbUrl, glbFile, onModelBounds }, ref) => {
  const [mode, setMode] = useState<'poly' | 'box' | null>(null);
  const [currentPoints, setCurrentPoints] = useState<Point[]>([]);
  const [shapes, setShapes] = useState<Shape[]>([]);
  const [gridSize, setGridSize] = useState(50);
  const [editingShapeId, setEditingShapeId] = useState<number | null>(null);
  //const [glbUrl, setGlbUrl] = useState<string | null>(null);
  const [hasFitted, setHasFitted] = useState(false);
  const wrapperRef = useRef<HTMLDivElement>(null);
  const [hoverPos, setHoverPos] = useState<Point | null>(null);
  const [hoverDomPos, setHoverDomPos] = useState<{ x: number; y: number } | null>(null);
  const [modelToStageScale, setModelToStageScale] = useState<{
    scaleX: number;
    scaleY: number;
    fitScale: number;
  } | null>(null);
  
  const [stageSize, setStageSize] = useState({
    width: window.innerWidth,
    height: window.innerHeight,
  });
  
  const [modelBounds, setModelBounds] = useState<{
    xmin: number;
    ymin: number;
    xmax: number;
    ymax: number;
  } | null>(null);
  
  const [stageScale, setStageScale] = useState(1);
  const [stagePosition, setStagePosition] = useState<Point>({ x: 0, y: 0 });

  const [contextMenu, setContextMenu] = useState<{
    visible: boolean;
    x: number;
    y: number;
    shapeId: number | null;
  }>({ visible: false, x: 0, y: 0, shapeId: null });

  const [isPanning, setIsPanning] = useState(false);
  const [lastPointerPos, setLastPointerPos] = useState<Point | null>(null);

  const stageRef = useRef<any>(null);

  const shapeStrokeWidth = Math.max(1, gridSize * 0.04);
  const vertexRadius = Math.max(2, gridSize * 0.1);

  const snapToGrid = (x: number, y: number): Point => {
    return {
      x: Math.round(x / gridSize) * gridSize,
      y: Math.round(y / gridSize) * gridSize,
    };
  };

  React.useEffect(() => {
    const updateSize = () => {
      if (wrapperRef.current) {
        const rect = wrapperRef.current.getBoundingClientRect();
        setStageSize({
          width: rect.width,
          height: rect.height,
        });
      }
    };
  
    updateSize();
  
    window.addEventListener("resize", updateSize);
    return () => window.removeEventListener("resize", updateSize);
  }, []);
  
  
  const handleModelBounds = (bounds: {
    xmin: number;
    xmax: number;
    ymin: number;
    ymax: number;
  }) => {
    if (hasFitted) return; // 이미 fit 했으면 아무것도 하지 않음
    setModelBounds(bounds);
    const { xmin, xmax, ymin, ymax } = bounds;
    const modelWidth = xmax - xmin;
    const modelHeight = ymax - ymin;
  
    const stageWidth = 800;
    const stageHeight = 600;
  
    const scaleX = stageWidth / modelWidth;
    const scaleY = stageHeight / modelHeight;
    const fitScale = Math.min(scaleX, scaleY, 1);
    setModelToStageScale({ scaleX, scaleY, fitScale });

    const centerX = xmin + modelWidth / 2;
    const centerY = ymin + modelHeight / 2;
  
    setStageScale(fitScale);
    setStagePosition({
      x: stageWidth / 2 - centerX * fitScale,
      y: stageHeight / 2 - centerY * fitScale,
    });
    setHasFitted(true);
    console.log(modelBounds);
  
  };
  
  

  const handleDragOver = (e: any) => {
    e.preventDefault();
  };

  const handleClick = (e: any) => {
    if (contextMenu.visible) {
      setContextMenu({ visible: false, x: 0, y: 0, shapeId: null });
      return;
    }

    const stage = e.target.getStage();
    const pointer = stage.getPointerPosition();
    if (!pointer) return;

    const snapped = snapToGrid(
      (pointer.x - stagePosition.x) / stageScale,
      (pointer.y - stagePosition.y) / stageScale
    );

    if (mode === 'poly') {
      setCurrentPoints([...currentPoints, snapped]);
    } else if (mode === 'box') {
      if (currentPoints.length === 0) {
        setCurrentPoints([snapped]);
      } else if (currentPoints.length === 1) {
        const p1 = currentPoints[0];
        const p2 = snapped;

        const xmin = Math.min(p1.x, p2.x);
        const xmax = Math.max(p1.x, p2.x);
        const ymin = Math.min(p1.y, p2.y);
        const ymax = Math.max(p1.y, p2.y);

        const canvasRect = {
            x: xmin,
            y: ymin,
            width: xmax - xmin,
            height: ymax - ymin,
          };
          let modelRect = undefined;

          if (modelBounds && modelToStageScale) {
                                
            console.log("Current Points", xmin, ymin, xmax, ymax);
          
            const snapPoints = snapToGrid(canvasRect.x, canvasRect.y)
            const worldxmin = snapPoints.x
            const worldxmax = snapPoints.x + canvasRect.width
            const worldymin = snapPoints.y
            const worldymax = canvasRect.y + canvasRect.height

            const modelXmin = worldxmin / modelToStageScale.scaleY + modelBounds.xmin
            const modelXmax = worldxmax / modelToStageScale.scaleY + modelBounds.xmin
            const modelYmax = modelBounds.ymax - worldymin / modelToStageScale.scaleY
            const modelYmin = modelBounds.ymax - worldymax / modelToStageScale.scaleY


              console.log(modelXmin, modelXmax, modelYmin, modelYmax);
            
              modelRect = {
                x: modelXmin,
                y: modelYmin,
                width: (modelXmax - modelXmin),
                height: (modelYmax - modelYmin)
              };
          
            console.log(modelRect);
          }
          
          


          const newShape: Shape = {
            id: Date.now(),
            type: 'box',
            canvasRect,
            modelRect,
          };

        setShapes([...shapes, newShape]);
        setCurrentPoints([]);
        setMode(null);
      }
    }
  };

  const handleFinishPoly = () => {
    if (currentPoints.length > 2) {
      const newShape: Shape = {
        id: Date.now(),
        type: 'poly',
        points: currentPoints,
      };


      let modelPoints = undefined;

      if (modelBounds && modelToStageScale) {
      const curModelPoints = currentPoints.map((p) => {
        const snapPoint = snapToGrid(p.x, p.y);
        const worldX = snapPoint.x
        const worldY = snapPoint.y
        const modelX = worldX / modelToStageScale.scaleY + modelBounds.xmin
        const modelY = modelBounds.ymax - worldY / modelToStageScale.scaleY
        return { x: modelX, y: modelY }
      })
      modelPoints = curModelPoints
      }
      newShape.modelPoints = modelPoints


      
      setShapes([...shapes, newShape]);
    }
    setCurrentPoints([]);
    setMode(null);
  };

  const handleDragVertex = (shapeId: number, index: number, pos: Point) => {
    setShapes((prevShapes) =>
      prevShapes.map((shape) => {
        if (shape.id !== shapeId) return shape;

        if (shape.type === 'poly') {
          const snapped = snapToGrid(pos.x, pos.y);
          const newPoints = [...shape.points];
          newPoints[index] = snapped;
        
          let modelPoints = shape.modelPoints;
          if (modelBounds && modelToStageScale) {
            modelPoints = newPoints.map((p) => {
              const worldX = p.x;
              const worldY = p.y;
              const modelX = worldX / modelToStageScale.scaleY + modelBounds.xmin;
              const modelY = modelBounds.ymax - worldY / modelToStageScale.scaleY;
              return { x: modelX, y: modelY };
            });
          }
        
          return { ...shape, points: newPoints, modelPoints };
        }
        

        if (shape.type === 'box') {
          const snapped = snapToGrid(pos.x, pos.y);
          const corners = getBoxCorners(shape.canvasRect);
          corners[index] = snapped;
        
          const newRect = {
            x: Math.min(corners[0].x, corners[2].x),
            y: Math.min(corners[0].y, corners[2].y),
            width: Math.abs(corners[2].x - corners[0].x),
            height: Math.abs(corners[2].y - corners[0].y),
          };
        
          let modelRect = shape.modelRect;
          if (modelBounds && modelToStageScale) {
            const snapPoints = snapToGrid(newRect.x, newRect.y);
            const worldxmin = snapPoints.x;
            const worldxmax = snapPoints.x + newRect.width;
            const worldymin = snapPoints.y;
            const worldymax = newRect.y + newRect.height;
        
            const modelXmin = worldxmin / modelToStageScale.scaleY + modelBounds.xmin;
            const modelXmax = worldxmax / modelToStageScale.scaleY + modelBounds.xmin;
            const modelYmax = modelBounds.ymax - worldymin / modelToStageScale.scaleY;
            const modelYmin = modelBounds.ymax - worldymax / modelToStageScale.scaleY;
        
            modelRect = {
              x: modelXmin,
              y: modelYmin,
              width: modelXmax - modelXmin,
              height: modelYmax - modelYmin,
            };
          }
        
          return { ...shape, canvasRect: newRect, modelRect };
        }
        

        return shape;
      })
    );
  };

  const getBoxCorners = (rect: {
    x: number;
    y: number;
    width: number;
    height: number;
  }): Point[] => {
    return [
      { x: rect.x, y: rect.y },
      { x: rect.x + rect.width, y: rect.y },
      { x: rect.x + rect.width, y: rect.y + rect.height },
      { x: rect.x, y: rect.y + rect.height },
    ];
  };
  const handleSelectShape = (shapeId: number, e: any) => {
    e.evt.preventDefault();
  
    const stage = stageRef.current;
    const pointerPos = stage.getPointerPosition();
    if (!pointerPos) return;
  
    const containerRect = stage.container().getBoundingClientRect();
  
    const domX =
      containerRect.left +
      pointerPos.x * stageScale +
      window.scrollX;
  
    const domY =
      containerRect.top +
      pointerPos.y * stageScale +
      window.scrollY;
  
    setEditingShapeId(shapeId);
    setContextMenu({
      visible: true,
      x: domX,
      y: domY,
      shapeId,
    });
  };
  
  

  const handleDeleteShape = () => {
    if (contextMenu.shapeId !== null) {
      setShapes((prev) =>
        prev.filter((shape) => shape.id !== contextMenu.shapeId)
      );
    }
    setContextMenu({ visible: false, x: 0, y: 0, shapeId: null });
  };

  const handleWheel = (e: any) => {
    e.evt.preventDefault();
    const stage = stageRef.current;
    const oldScale = stage.scaleX();

    const pointer = stage.getPointerPosition();
    if (!pointer) return;

    const mousePointTo = {
      x: (pointer.x - stage.x()) / oldScale,
      y: (pointer.y - stage.y()) / oldScale,
    };

    const scaleBy = 1.05;
    const direction = e.evt.deltaY > 0 ? -1 : 1;
    const newScale =
      direction > 0 ? oldScale * scaleBy : oldScale / scaleBy;

    setStageScale(newScale);
    const newPos = {
      x: pointer.x - mousePointTo.x * newScale,
      y: pointer.y - mousePointTo.y * newScale,
    };
    setStagePosition(newPos);
  };


  useImperativeHandle(ref, () => ({
    getShapes: () => shapes,
    getStageScale: () => stageScale,
    getModelBounds: () => modelBounds,
    setShapes: (newShapes: Shape[]) => setShapes(newShapes), // ✅ 추가

  }));
  return (
    <div style={{ 
      padding: 24,
      backgroundColor: '#fff',
       minHeight: '100vh',
       borderRadius: '24px',
       }}>


      <div style={{ marginBottom: 10 }}>
        <button
         style={{
          backgroundColor: mode === 'poly' ? '#007bff' : '#fff',
          color: mode === 'poly' ? '#fff' : '#000',
          border: '1px solid #007bff',
          borderRadius: '4px',
          padding: '8px 16px',
          cursor: 'pointer',
          marginRight: '10px',
         }}
        onClick={() => setMode('poly')}>Poly</button>
        <button 
        style={{
          backgroundColor: mode === 'box' ? '#007bff' : '#fff',
          color: mode === 'box' ? '#fff' : '#000',
          border: '1px solid #007bff',
          borderRadius: '4px',
          padding: '8px 16px',
          cursor: 'pointer',
          marginRight: '10px',
         }}
        onClick={() => setMode('box')}>Box</button>
        {mode === 'poly' && (
          <button onClick={handleFinishPoly} style={{ marginLeft: 10 }}>
            Finish Poly
          </button>
        )}
        <span style={{ marginLeft: 20 }}>
          Grid Size:
          <input
          style={{
            backgroundColor: '#fff',
            color: '#000',
            border: '1px solid #007bff',
            borderRadius: '4px',
            padding: '8px 16px',
            width: 80,
            marginLeft: 5,
          }}  
            type="number"
            value={gridSize}
            onChange={(e) => setGridSize(Number(e.target.value))}
            
          />
        </span>
      </div>
      <div ref={wrapperRef} style={{ width: "100%", height: "100vh" }}>

      <Stage
         width={stageSize.width}
         height={stageSize.height}
        ref={stageRef}
        scaleX={stageScale}
        scaleY={stageScale}
        x={stagePosition.x}
        y={stagePosition.y}
        onClick={handleClick}
        onWheel={handleWheel}
        onMouseDown={(e) => {
            if (e.evt.button === 1) {
              setIsPanning(true);
              document.body.style.overflow = "hidden"; // ★ 추가
              const pos = stageRef.current.getPointerPosition();
              if (pos) setLastPointerPos(pos);
            }
          }}
          onMouseMove={(e) => {
            if (isPanning && lastPointerPos) {
              const pos = stageRef.current.getPointerPosition();
              if (!pos) return;
          
              const dx = pos.x - lastPointerPos.x;
              const dy = pos.y - lastPointerPos.y;
          
              setStagePosition((prev) => ({
                x: prev.x + dx,
                y: prev.y + dy,
              }));
              setLastPointerPos(pos);
            }
          
            const stage = stageRef.current;
            const pointer = stage.getPointerPosition();
            if (!pointer) {
            setHoverPos(null);
            return;
            }

            if (modelBounds && modelToStageScale) {
                const worldX = (pointer.x - stagePosition.x) / stageScale;
                const worldY = (pointer.y - stagePosition.y) / stageScale;
              
                const modelX = worldX / modelToStageScale.scaleY + modelBounds.xmin;
                const modelY = modelBounds.ymax - (worldY / modelToStageScale.scaleY);
              
                setHoverPos({ x: modelX, y: modelY });
              } else {
                const worldX = (pointer.x - stagePosition.x) / stageScale;
                const worldY = (pointer.y - stagePosition.y) / stageScale;
              
                setHoverPos({ x: worldX, y: worldY });
              }
              

          
            // DOM 좌표도 저장 (화면에 띄우기용)
            const containerRect = stage.container().getBoundingClientRect();
            setHoverDomPos({
              x: containerRect.left + pointer.x + window.scrollX + 10,
              y: containerRect.top + pointer.y + window.scrollY + 10,
            });
          }}
          
        onMouseLeave={() => {
            setHoverPos(null);
            setHoverDomPos(null);
          }}
          
        onMouseUp={() => {
            setIsPanning(false);
            setLastPointerPos(null);
            document.body.style.overflow = ""; // ★ 추가
          }}
        style={{ border: '1px solid gray', cursor: isPanning ? 'grab' : 'default' }}
      >
        {(glbUrl || glbFile) && (
        <GLBLayer
            glbUrl={glbUrl ?? undefined}
            glbFile={glbFile ?? undefined}
            voxelCount={50}
            onBounds={handleModelBounds}

        />
        )}

        <Layer>
          {(() => {
            const worldLeft = -stagePosition.x / stageScale;
            const worldTop = -stagePosition.y / stageScale;
            const worldRight = (stageSize.width - stagePosition.x) / stageScale;
            const worldBottom = (stageSize.height - stagePosition.y) / stageScale;
            

            const gridLineWidth = Math.max(1, gridSize / 20);

            const vLines = [];
            const startX = Math.floor(worldLeft / gridSize) * gridSize;
            const endX = Math.ceil(worldRight / gridSize) * gridSize;
            for (let x = startX; x * stageScale + stagePosition.x < stageSize.width; x += gridSize) {
              vLines.push(
                <Line
                  key={`v-${x}`}
                  points={[x, worldTop, x, worldBottom]}
                  stroke="#ddd"
                  strokeWidth={gridLineWidth}
                />
              );
            }

            const hLines = [];
            const startY = Math.floor(worldTop / gridSize) * gridSize;
            const endY = Math.ceil(worldBottom / gridSize) * gridSize;
            for (let y = startY; y * stageScale + stagePosition.y < stageSize.height; y += gridSize) {

              hLines.push(
                <Line
                  key={`h-${y}`}
                  points={[worldLeft, y, worldRight, y]}
                  stroke="#ddd"
                  strokeWidth={gridLineWidth}
                />
              );
            }

            return [...vLines, ...hLines];
          })()}

          {shapes.map((shape) => {
            if (shape.type === 'poly') {
              return (
                <Line
                  key={shape.id}
                  points={shape.points.flatMap((p) => [p.x, p.y])}
                  closed
                  fill="rgba(255, 0, 0, 0.3)"
                  stroke="red"
                  strokeWidth={shapeStrokeWidth}
                  onClick={(e) => {
                    e.cancelBubble = true;
                    setEditingShapeId(shape.id);
                  }}
                  onContextMenu={(e) => handleSelectShape(shape.id, e)}
                />
              );
            } else if (shape.type === 'box') {
              return (
                <Rect
                  key={shape.id}
                  x={shape.canvasRect.x}
                  y={shape.canvasRect.y}
                  width={shape.canvasRect.width}
                  height={shape.canvasRect.height}
                  fill="rgba(255, 0, 0, 0.3)"
                  stroke="red"
                  strokeWidth={shapeStrokeWidth}
                  onClick={(e) => {
                    e.cancelBubble = true;
                    setEditingShapeId(shape.id);
                  }}
                  onContextMenu={(e) => handleSelectShape(shape.id, e)}
                />
              );
            }
            return null;
          })}

          {editingShapeId &&
            shapes
              .filter((s) => s.id === editingShapeId)
              .flatMap((shape) => {
                if (shape.type === 'poly') {
                  return shape.points.map((p, i) => (
                    <Circle
                      key={i}
                      x={p.x}
                      y={p.y}
                      radius={vertexRadius}
                      fill="blue"
                      draggable
                      onDragMove={(e) => {
                        handleDragVertex(shape.id, i, {
                          x: e.target.x(),
                          y: e.target.y(),
                        });
                      }}
                    />
                  ));
                } else if (shape.type === 'box') {
                  const corners = getBoxCorners(shape.canvasRect);
                  return corners.map((p, i) => (
                    <Circle
                      key={i}
                      x={p.x}
                      y={p.y}
                      radius={vertexRadius}
                      fill="blue"
                      draggable
                      onDragMove={(e) => {
                        handleDragVertex(shape.id, i, {
                          x: e.target.x(),
                          y: e.target.y(),
                        });
                      }}
                    />
                  ));
                }
                return [];
              })}

          {currentPoints.length > 0 && (
            <>
              {mode === 'poly' && (
                <Line
                  points={currentPoints.flatMap((p) => [p.x, p.y])}
                  closed={false}
                  stroke="red"
                  strokeWidth={shapeStrokeWidth}
                />
              )}

              {mode === 'box' && currentPoints.length === 2 && (
                <Rect
                  x={Math.min(currentPoints[0].x, currentPoints[1].x)}
                  y={Math.min(currentPoints[0].y, currentPoints[1].y)}
                  width={Math.abs(currentPoints[1].x - currentPoints[0].x)}
                  height={Math.abs(currentPoints[1].y - currentPoints[0].y)}
                  stroke="red"
                  dash={[4, 4]}
                  strokeWidth={shapeStrokeWidth}
                  fill="rgba(255,0,0,0.1)"
                />
              )}

              {currentPoints.map((p, i) => (
                <Circle
                  key={i}
                  x={p.x}
                  y={p.y}
                  radius={vertexRadius}
                  fill="blue"
                  draggable
                  onDragMove={(e) => {
                    const snapped = snapToGrid(e.target.x(), e.target.y());
                    const newPts = [...currentPoints];
                    newPts[i] = snapped;
                    setCurrentPoints(newPts);
                  }}
                />
              ))}
            </>
          )}
        </Layer>
      </Stage>
      </div>
      {contextMenu.visible && (
        <div
          style={{
            position: 'absolute',
            top: contextMenu.y,
            left: contextMenu.x,
            backgroundColor: 'white',
            border: '1px solid #999',
            padding: 5,
            zIndex: 10,
          }}
        >
          <button onClick={handleDeleteShape}>삭제</button>
        </div>
      )}
      {hoverPos && hoverDomPos && (
        <div
            style={{
            position: 'absolute',
            top: hoverDomPos.y,
            left: hoverDomPos.x,
            backgroundColor: 'white',
            border: '1px solid #999',
            fontSize: 12,
            padding: '2px 4px',
            pointerEvents: 'none',
            zIndex: 100,
            }}
        >
            ({hoverPos.x.toFixed(3)}, {hoverPos.y.toFixed(3)})
        </div>
        )}
    </div>
  );
});

export default DrawingCanvas;
