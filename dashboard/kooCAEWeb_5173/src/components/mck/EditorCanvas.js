import { jsx as _jsx, Fragment as _Fragment, jsxs as _jsxs } from "react/jsx-runtime";
import React, { useRef, useState } from 'react';
import { useDrop } from 'react-dnd';
import { Stage, Layer, Rect, Text, Line, Circle } from 'react-konva';
import { ItemTypes } from './BlockPalette';
import { Card } from 'antd';
// ✅ springPathPoints
function springPathPoints(x1, y1, x2, y2, segments = 6, amplitude = 10) {
    const snapThreshold = 10;
    let dx = x2 - x1;
    let dy = y2 - y1;
    if (Math.abs(dx) < snapThreshold) {
        dx = 0;
    }
    if (Math.abs(dy) < snapThreshold) {
        dy = 0;
    }
    const length = Math.sqrt(dx * dx + dy * dy);
    const angle = length === 0 ? 0 : Math.atan2(dy, dx);
    const step = length / (segments * 2);
    const points = [];
    points.push(x1, y1);
    for (let i = 1; i <= segments * 2 - 1; i++) {
        const dir = i % 2 === 0 ? 1 : -1;
        const x = step * i;
        const y = amplitude * dir;
        const rotatedX = x * Math.cos(angle) - y * Math.sin(angle) + x1;
        const rotatedY = x * Math.sin(angle) + y * Math.cos(angle) + y1;
        points.push(rotatedX, rotatedY);
    }
    points.push(x2, y2);
    return points;
}
// ✅ autoLayout
function autoLayout(system) {
    const minWidth = 50;
    const spacing = 20;
    const tolerance = 10;
    const baseWidths = {};
    system.masses.forEach((m) => {
        baseWidths[m.id] = minWidth;
    });
    const connectedMasses = {};
    system.masses.forEach((m) => {
        connectedMasses[m.id] = { top: [], bottom: [] };
    });
    system.springs.forEach((spring) => {
        const from = spring.from;
        const to = spring.to;
        const fromMass = system.masses.find((m) => m.id === from);
        const toMass = system.masses.find((m) => m.id === to);
        if (fromMass && toMass) {
            const dy = toMass.y - fromMass.y;
            if (Math.abs(dy) < tolerance) {
                connectedMasses[from].bottom.push(to);
                connectedMasses[to].top.push(from);
            }
            else if (dy < 0) {
                connectedMasses[from].top.push(to);
                connectedMasses[to].bottom.push(from);
            }
            else {
                connectedMasses[from].bottom.push(to);
                connectedMasses[to].top.push(from);
            }
        }
    });
    const requiredWidths = {};
    for (const mass of system.masses) {
        let requiredWidthTop = minWidth;
        let requiredWidthBottom = minWidth;
        const topIds = connectedMasses[mass.id].top;
        const bottomIds = connectedMasses[mass.id].bottom;
        if (topIds.length > 0) {
            const totalTopWidth = topIds.reduce((sum, id) => sum + baseWidths[id], 0) +
                spacing * Math.max(0, topIds.length - 1);
            requiredWidthTop = totalTopWidth;
        }
        if (bottomIds.length > 0) {
            const totalBottomWidth = bottomIds.reduce((sum, id) => sum + baseWidths[id], 0) +
                spacing * Math.max(0, bottomIds.length - 1);
            requiredWidthBottom = totalBottomWidth;
        }
        requiredWidths[mass.id] = Math.max(requiredWidthTop, requiredWidthBottom, minWidth);
    }
    const rows = {};
    system.masses.forEach((mass) => {
        let found = false;
        for (const y of Object.keys(rows).map(Number)) {
            if (Math.abs(y - mass.y) < tolerance) {
                rows[y].push(mass);
                found = true;
                break;
            }
        }
        if (!found) {
            rows[mass.y] = [mass];
        }
    });
    const newMasses = [];
    for (const [yStr, masses] of Object.entries(rows)) {
        const y = Number(yStr);
        const massesWithWidths = masses.map((m) => ({
            ...m,
            width: requiredWidths[m.id],
        }));
        const avgWidth = massesWithWidths.reduce((sum, m) => sum + m.width, 0) /
            massesWithWidths.length;
        const rowSpacing = avgWidth + 30;
        const centerX = massesWithWidths.reduce((sum, m) => sum + m.x, 0) /
            massesWithWidths.length;
        const totalWidth = rowSpacing * (massesWithWidths.length - 1);
        let startX = centerX - totalWidth / 2;
        massesWithWidths.forEach((m, idx) => {
            newMasses.push({
                ...m,
                x: startX + idx * rowSpacing,
                y,
                width: m.width,
            });
        });
    }
    return {
        ...system,
        masses: newMasses,
    };
}
// ✅ helper
const findNodeById = (system, id) => {
    return (system.masses.find((m) => m.id === id) ||
        system.fixedPoints?.find((fp) => fp.id === id));
};
const nodeCenterX = (node) => node.x + (node.width || 0) / 2;
const nodeCenterY = (node) => node.y + (node.height ? node.height / 2 : 0);
const EditorCanvas = ({ selectedTool, onClearTool, onSelect, system, setSystem, massIdCounter, setMassIdCounter, springIdCounter, setSpringIdCounter, damperIdCounter, setDamperIdCounter, fixedIdCounter, setFixedIdCounter, }) => {
    const [pendingSpring, setPendingSpring] = useState(null);
    const [pendingDamper, setPendingDamper] = useState(null);
    const containerRef = useRef(null);
    const [, drop] = useDrop({
        accept: [ItemTypes.MASS, ItemTypes.FIXED],
        drop: (item, monitor) => {
            const clientOffset = monitor.getClientOffset();
            if (!clientOffset || !containerRef.current)
                return;
            const containerBox = containerRef.current.getBoundingClientRect();
            const x = clientOffset.x - containerBox.left;
            const y = clientOffset.y - containerBox.top;
            if (item.type === ItemTypes.MASS) {
                const newMass = {
                    id: `mass-${massIdCounter}`,
                    m: 1,
                    x,
                    y,
                };
                setSystem((prev) => {
                    const updated = {
                        ...prev,
                        masses: [...prev.masses, newMass],
                    };
                    return autoLayout(updated);
                });
                setMassIdCounter((prev) => prev + 1);
            }
            else if (item.type === ItemTypes.FIXED) {
                const newFixed = {
                    id: `fixed-${fixedIdCounter}`,
                    x,
                    y,
                };
                setSystem((prev) => ({
                    ...prev,
                    fixedPoints: [...(prev.fixedPoints || []), newFixed],
                }));
                setFixedIdCounter((prev) => prev + 1);
            }
        },
    });
    const handleNodeClick = (nodeId) => {
        if (selectedTool === ItemTypes.SPRING) {
            if (!pendingSpring) {
                setPendingSpring(nodeId);
            }
            else {
                if (pendingSpring === nodeId) {
                    setPendingSpring(null);
                    onClearTool();
                    return;
                }
                const newSpring = {
                    id: `spring-${springIdCounter}`,
                    type: 'spring',
                    from: pendingSpring,
                    to: nodeId,
                    k: 1000,
                };
                setSystem((prev) => ({
                    ...prev,
                    springs: [...prev.springs, newSpring],
                }));
                setSpringIdCounter((prev) => prev + 1);
                setPendingSpring(null);
                onClearTool();
            }
        }
        else if (selectedTool === ItemTypes.DAMPER) {
            if (!pendingDamper) {
                setPendingDamper(nodeId);
            }
            else {
                if (pendingDamper === nodeId) {
                    setPendingDamper(null);
                    onClearTool();
                    return;
                }
                const newDamper = {
                    id: `damper-${damperIdCounter}`,
                    type: 'damper',
                    from: pendingDamper,
                    to: nodeId,
                    c: 10,
                };
                setSystem((prev) => ({
                    ...prev,
                    dampers: [...prev.dampers, newDamper],
                }));
                setDamperIdCounter((prev) => prev + 1);
                setPendingDamper(null);
                onClearTool();
            }
        }
        else {
            console.log('Normal node click:', nodeId);
        }
    };
    return (_jsx(Card, { title: selectedTool === ItemTypes.SPRING
            ? pendingSpring
                ? 'Select second node for Spring'
                : 'Select first node for Spring'
            : selectedTool === ItemTypes.DAMPER
                ? pendingDamper
                    ? 'Select second node for Damper'
                    : 'Select first node for Damper'
                : 'Editor Canvas', style: { width: 800, height: 600 }, children: _jsx("div", { ref: (node) => {
                containerRef.current = node;
                drop(node);
            }, style: {
                width: 800,
                height: 600,
                position: 'relative',
            }, children: _jsx(Stage, { width: 800, height: 600, children: _jsxs(Layer, { children: [_jsx(Text, { text: "Drag Mass, Fixed, or use Spring/Damper Tool", x: 20, y: 20 }), system.springs.map((spring) => {
                            const from = findNodeById(system, spring.from);
                            const to = findNodeById(system, spring.to);
                            if (!from || !to)
                                return null;
                            return (_jsx(Line, { points: springPathPoints(nodeCenterX(from), nodeCenterY(from), nodeCenterX(to), nodeCenterY(to), 6, 10), stroke: "#2ecc71", strokeWidth: 2, onClick: () => {
                                    onSelect({
                                        type: 'spring',
                                        data: spring,
                                    });
                                } }, spring.id));
                        }), system.dampers.map((damper) => {
                            const from = findNodeById(system, damper.from);
                            const to = findNodeById(system, damper.to);
                            if (!from || !to)
                                return null;
                            return (_jsx(Line, { points: [
                                    nodeCenterX(from),
                                    nodeCenterY(from),
                                    nodeCenterX(to),
                                    nodeCenterY(to),
                                ], stroke: "#e67e22", strokeWidth: 4, dash: [10, 5], onClick: () => {
                                    onSelect({
                                        type: 'damper',
                                        data: damper,
                                    });
                                } }, damper.id));
                        }), system.fixedPoints?.map((fp) => (_jsx(Circle, { x: fp.x, y: fp.y, radius: 10, fill: "#2c3e50", stroke: "black", strokeWidth: 2, onClick: () => {
                                handleNodeClick(fp.id);
                                onSelect({
                                    type: 'fixed',
                                    data: fp,
                                });
                            } }, fp.id))), system.masses.map((mass) => (_jsx(React.Fragment, { children: mass.m === 0 ? (_jsx(Circle, { x: mass.x + (mass.width || 50) / 2, y: mass.y + 25, radius: 15, fill: "red", stroke: "black", strokeWidth: 2, onMouseDown: (e) => {
                                    handleNodeClick(mass.id);
                                    onSelect({
                                        type: 'mass',
                                        data: mass,
                                    });
                                    e.cancelBubble = true;
                                }, draggable: true, onDragEnd: (e) => {
                                    const grid = 10;
                                    const newX = Math.round(e.target.x() - (mass.width || 50) / 2);
                                    const newY = Math.round(e.target.y() - 25);
                                    setSystem((prev) => {
                                        const updated = {
                                            ...prev,
                                            masses: prev.masses.map((m) => m.id === mass.id
                                                ? { ...m, x: newX, y: newY }
                                                : m),
                                        };
                                        return autoLayout(updated);
                                    });
                                } })) : (_jsxs(_Fragment, { children: [_jsx(Rect, { x: mass.x, y: mass.y, width: mass.width || 50, height: 50, fill: "#2980b9", stroke: "black", strokeWidth: 2, draggable: true, onDragEnd: (e) => {
                                            const grid = 10;
                                            const newX = Math.round(e.target.x() / grid) * grid;
                                            const newY = Math.round(e.target.y() / grid) * grid;
                                            setSystem((prev) => {
                                                const updated = {
                                                    ...prev,
                                                    masses: prev.masses.map((m) => m.id === mass.id
                                                        ? { ...m, x: newX, y: newY }
                                                        : m),
                                                };
                                                return autoLayout(updated);
                                            });
                                        }, onMouseDown: (e) => {
                                            handleNodeClick(mass.id);
                                            onSelect({
                                                type: 'mass',
                                                data: mass,
                                            });
                                            e.cancelBubble = true;
                                        } }), _jsx(Text, { text: mass.id.replace(/^mass-/, ''), x: mass.x, y: mass.y + 15, width: mass.width || 50, height: 50, fontSize: 16, fill: "#fff", align: "center", verticalAlign: "middle" })] })) }, mass.id)))] }) }) }) }));
};
export default EditorCanvas;
