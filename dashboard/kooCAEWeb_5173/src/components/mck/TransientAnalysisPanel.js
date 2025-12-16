import { jsx as _jsx, jsxs as _jsxs, Fragment as _Fragment } from "react/jsx-runtime";
import { useState } from "react";
import { Card, Form, Select, Input, InputNumber, Button, Table, message, Space, } from "antd";
import TextArea from "antd/es/input/TextArea";
import PWMGenerator from "../PWMGenerator";
const { Option } = Select;
const TransientAnalysisPanel = ({ nodes, onAddForce, onRunTransient, onDeleteForce, forces, }) => {
    const [inputType, setInputType] = useState("function");
    const [form] = Form.useForm();
    const handlePasteTable = (e) => {
        const pasted = e.clipboardData.getData("Text");
        const rows = pasted
            .trim()
            .split(/\r?\n/)
            .map((line) => line
            .trim()
            .split(/[\t, ]+/)
            .map(Number));
        const t = [];
        const f = [];
        rows.forEach(([time, force]) => {
            if (!isNaN(time) && !isNaN(force)) {
                t.push(time);
                f.push(force);
            }
        });
        form.setFieldsValue({
            timeArray: t,
            forceArray: f,
            duration: Math.max(...t),
        });
        message.success(`Pasted ${t.length} points from clipboard`);
    };
    const handleAddForce = async () => {
        try {
            const values = await form.validateFields();
            let newForce;
            if (inputType === "function") {
                newForce = {
                    nodeId: values.nodeId,
                    type: "function",
                    expression: values.expression,
                    duration: values.duration,
                    dt: values.dt,
                };
            }
            else if (inputType === "table" || inputType === "pwm") {
                newForce = {
                    nodeId: values.nodeId,
                    type: "table",
                    timeArray: values.timeArray ?? [],
                    forceArray: values.forceArray ?? [],
                    duration: values.duration,
                    dt: values.dt,
                    pwmChannel: values.pwmChannel,
                };
            }
            else {
                return;
            }
            onAddForce(newForce);
            form.setFieldsValue({
                nodeId: nodes[0]?.id || null,
                duration: 1,
                dt: 0.001,
                expression: "10*sin(2*pi*50*t)",
                timeArray: [],
                forceArray: [],
                pwmChannel: "",
            });
        }
        catch (err) {
            console.error("Validation failed", err);
            if (err?.errorFields) {
                err.errorFields.forEach((field) => {
                    console.error(`Field ${field.name} - Errors:`, field.errors);
                });
            }
            message.error("Please check the form inputs.");
        }
    };
    const handleRunTransient = async () => {
        try {
            await onRunTransient();
        }
        catch (e) {
            console.error("Transient run error", e);
            message.error("Error during transient analysis.");
        }
    };
    const tableColumns = [
        { title: "Node", dataIndex: "nodeId" },
        { title: "Type", dataIndex: "type" },
        {
            title: "Expression / Data",
            render: (_, rec) => {
                if (rec.type === "function") {
                    return rec.expression;
                }
                else if (rec.type === "table") {
                    if (Array.isArray(rec.timeArray)) {
                        return `${rec.timeArray.length} points`;
                    }
                    else {
                        return "0 points";
                    }
                }
                else {
                    return rec.pwmChannel;
                }
            },
        },
        { title: "Duration", dataIndex: "duration" },
        {
            title: "Action",
            render: (_, rec) => {
                const key = `${rec.nodeId}-${rec.type}-${rec.expression || rec.pwmChannel || ""}`;
                return (_jsx(Button, { danger: true, size: "small", onClick: () => onDeleteForce(key), children: "Delete" }));
            },
        },
    ];
    return (_jsx(Card, { size: "small", title: "Transient Analysis", children: _jsxs(Space, { direction: "vertical", style: { width: "100%" }, children: [_jsxs(Select, { value: inputType, onChange: (v) => setInputType(v), style: { width: 200 }, children: [_jsx(Option, { value: "function", children: "Function" }), _jsx(Option, { value: "pwm", children: "PWM" }), _jsx(Option, { value: "table", children: "Table" })] }), _jsxs(Form, { layout: "vertical", form: form, initialValues: {
                        nodeId: nodes[0]?.id || null,
                        duration: 1,
                        dt: 0.001,
                        expression: "10*sin(2*pi*50*t)",
                        timeArray: [],
                        forceArray: [],
                    }, children: [_jsx(Form.Item, { label: "Target Node", name: "nodeId", rules: [{ required: true }], children: _jsx(Select, { children: nodes.map((n) => (_jsx(Option, { value: n.id, children: n.id }, n.id))) }) }), inputType === "function" && (_jsxs(_Fragment, { children: [_jsx(Form.Item, { label: "Expression", name: "expression", rules: [{ required: true }], children: _jsx(Input, { placeholder: "e.g. 10*sin(2*pi*50*t)" }) }), _jsx(Form.Item, { label: "Duration (s)", name: "duration", rules: [{ required: true }], children: _jsx(InputNumber, { min: 0.01, step: 0.01, style: { width: "100%" } }) }), _jsx(Form.Item, { label: "dt (s)", name: "dt", rules: [{ required: true }], children: _jsx(InputNumber, { min: 0.000001, step: 0.000001, style: { width: "100%" } }) })] })), inputType === "table" && (_jsxs(_Fragment, { children: [_jsx(Form.Item, { label: "Paste Time-Force Table", children: _jsx(TextArea, { rows: 4, onPaste: handlePasteTable, placeholder: "Paste 2 columns here" }) }), _jsx(Form.Item, { shouldUpdate: true, noStyle: true, children: () => {
                                        const values = form.getFieldsValue();
                                        const timeArr = values.timeArray || [];
                                        const forceArr = values.forceArray || [];
                                        return timeArr.length > 0 ? (_jsx(Table, { size: "small", columns: [
                                                { title: "Time", dataIndex: "time" },
                                                { title: "Force", dataIndex: "force" },
                                            ], dataSource: timeArr.map((t, i) => ({
                                                key: i,
                                                time: t,
                                                force: forceArr[i],
                                            })), pagination: false, style: { marginTop: 8 } })) : null;
                                    } }), _jsx(Form.Item, { label: "Duration (s)", name: "duration", rules: [{ required: true }], children: _jsx(InputNumber, { min: 0.01, step: 0.01, style: { width: "100%" } }) }), _jsx(Form.Item, { label: "dt (s)", name: "dt", rules: [{ required: true }], children: _jsx(InputNumber, { min: 0.000001, step: 0.000001, style: { width: "100%" } }) })] })), inputType === "pwm" && (_jsx(_Fragment, { children: _jsx(PWMGenerator, { onPWMGenerated: (result) => {
                                    onAddForce({
                                        nodeId: form.getFieldValue("nodeId"),
                                        type: "table",
                                        timeArray: result.t,
                                        forceArray: result.PWM,
                                        duration: result.duration,
                                        dt: result.dt,
                                        pwmChannel: result.channelName,
                                    });
                                } }) })), inputType !== "pwm" && (_jsx(Button, { type: "primary", onClick: handleAddForce, children: "Add Force" }))] }), _jsx(Table, { size: "small", columns: tableColumns, dataSource: forces || [], rowKey: (rec) => `${rec.nodeId}-${rec.type}-${rec.expression || rec.pwmChannel || ""}`, pagination: false }), _jsx(Button, { type: "primary", block: true, onClick: handleRunTransient, children: "Run Transient Analysis" })] }) }));
};
export default TransientAnalysisPanel;
