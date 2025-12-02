import { jsx as _jsx, jsxs as _jsxs, Fragment as _Fragment } from "react/jsx-runtime";
import { useState } from "react";
import { Form, InputNumber, Input, Button, Checkbox, Row, Col, Card, Table, Popconfirm, message, Modal, } from "antd";
import Plot from "react-plotly.js";
import { generatePWM } from "../utils/pwmGenerator";
import { DownloadOutlined, PlusOutlined } from "@ant-design/icons";
const PWMGenerator = ({ onPWMGenerated }) => {
    const [form] = Form.useForm();
    const [channels, setChannels] = useState([
        {
            name: "Channel 1",
            frequency: 875,
            amplitude: 10,
            coefficient: 8,
            enabled: true,
        },
    ]);
    const [plotData, setPlotData] = useState(null);
    const [isModalOpen, setIsModalOpen] = useState(false);
    const [batchForm] = Form.useForm();
    const handleAddChannel = () => {
        const newChannel = {
            name: `Channel ${channels.length + 1}`,
            frequency: 1000,
            amplitude: 10,
            coefficient: 8,
            enabled: true,
        };
        setChannels([...channels, newChannel]);
    };
    const handleDeleteChannel = (index) => {
        const newChannels = [...channels];
        newChannels.splice(index, 1);
        setChannels(newChannels);
    };
    const handleChannelChange = (index, key, value) => {
        const newChannels = [...channels];
        newChannels[index][key] = value;
        setChannels(newChannels);
    };
    const onFinish = (values) => {
        const config = {
            targetFrequency: values.targetFrequency,
            sinAmplitude: values.sinAmplitude,
            dt: values.dt,
            duration: values.duration,
            channels,
        };
        const result = generatePWM(config);
        console.log("PWM generation result:", result);
        setPlotData(result);
        message.success("PWM Generated!");
        if (onPWMGenerated) {
            onPWMGenerated({
                channelName: channels[0]?.name || "PWM_Channel",
                duration: values.duration,
                dt: values.dt,
                t: result.t,
                PWM: result.PWM,
            });
        }
    };
    const downloadCSV = () => {
        if (!plotData)
            return;
        let content = "time,PWM\n";
        for (let i = 0; i < plotData.t.length; i++) {
            content += `${plotData.t[i]},${plotData.PWM[i]}\n`;
        }
        const blob = new Blob([content], { type: "text/csv;charset=utf-8" });
        const link = document.createElement("a");
        link.href = window.URL.createObjectURL(blob);
        link.download = "PWM.csv";
        link.click();
    };
    return (_jsxs(Card, { title: "PWM Generator", bordered: true, children: [_jsxs(Form, { layout: "vertical", form: form, initialValues: {
                    targetFrequency: 167.5,
                    sinAmplitude: 10,
                    dt: 0.00001,
                    duration: 0.05,
                }, onFinish: onFinish, children: [_jsxs(Row, { gutter: 16, children: [_jsx(Col, { span: 6, children: _jsx(Form.Item, { label: "Target Frequency (Hz)", name: "targetFrequency", children: _jsx(InputNumber, { min: 1, step: 0.1, style: { width: "100%" } }) }) }), _jsx(Col, { span: 6, children: _jsx(Form.Item, { label: "Sin Amplitude", name: "sinAmplitude", children: _jsx(InputNumber, { min: 0.1, step: 0.1, style: { width: "100%" } }) }) }), _jsx(Col, { span: 6, children: _jsx(Form.Item, { label: "dt (s)", name: "dt", children: _jsx(InputNumber, { min: 0.000001, step: 0.000001, style: { width: "100%" } }) }) }), _jsx(Col, { span: 6, children: _jsx(Form.Item, { label: "Duration (s)", name: "duration", children: _jsx(InputNumber, { min: 0.01, step: 0.01, style: { width: "100%" } }) }) })] }), _jsxs(Card, { size: "small", title: "PWM Channels", style: { marginTop: 16 }, children: [_jsx(Button, { type: "primary", style: { marginBottom: 16 }, onClick: () => setIsModalOpen(true), children: "Batch Add Channels" }), _jsx(Table, { dataSource: channels, pagination: false, rowKey: "name", columns: [
                                    {
                                        title: "Name",
                                        dataIndex: "name",
                                        render: (text, record, index) => (_jsx(Input, { value: text, onChange: (e) => handleChannelChange(index, "name", e.target.value) })),
                                    },
                                    {
                                        title: "Frequency (Hz)",
                                        dataIndex: "frequency",
                                        render: (value, record, index) => (_jsx(InputNumber, { value: value, min: 1, onChange: (v) => handleChannelChange(index, "frequency", v) })),
                                    },
                                    {
                                        title: "Amplitude",
                                        dataIndex: "amplitude",
                                        render: (value, record, index) => (_jsx(InputNumber, { value: value, onChange: (v) => handleChannelChange(index, "amplitude", v) })),
                                    },
                                    {
                                        title: "Coefficient",
                                        dataIndex: "coefficient",
                                        render: (value, record, index) => (_jsx(InputNumber, { value: value, onChange: (v) => handleChannelChange(index, "coefficient", v) })),
                                    },
                                    {
                                        title: "Enabled",
                                        dataIndex: "enabled",
                                        render: (value, record, index) => (_jsx(Checkbox, { checked: value, onChange: (e) => handleChannelChange(index, "enabled", e.target.checked) })),
                                    },
                                    {
                                        title: "Actions",
                                        key: "actions",
                                        render: (_, record, index) => (_jsx(Popconfirm, { title: "Delete this channel?", onConfirm: () => handleDeleteChannel(index), children: _jsx(Button, { danger: true, size: "small", children: "Delete" }) })),
                                    },
                                ] }), _jsx(Button, { type: "dashed", icon: _jsx(PlusOutlined, {}), style: { marginTop: 12 }, onClick: handleAddChannel, children: "Add Channel" })] }), _jsx(Button, { type: "primary", htmlType: "button", block: true, style: { marginTop: 16 }, onClick: () => {
                            form.submit();
                        }, children: "Generate PWM" })] }), plotData && (_jsxs(_Fragment, { children: [_jsx(Plot, { data: [
                            {
                                x: plotData.t,
                                y: plotData.SinX,
                                type: "scatter",
                                mode: "lines",
                                name: "Sin Wave",
                            },
                        ], layout: {
                            title: { text: "Sine Wave" },
                            height: 300,
                        } }), _jsx(Plot, { data: plotData.SawX.map((saw, idx) => ({
                            x: plotData.t,
                            y: saw,
                            type: "scatter",
                            mode: "lines",
                            name: `SawX[${idx}]`,
                        })), layout: {
                            title: { text: "Sawtooth Waves" },
                            height: 300,
                        } }), _jsx(Plot, { data: [
                            {
                                x: plotData.t,
                                y: plotData.PWM,
                                type: "scatter",
                                mode: "lines",
                                name: "PWM",
                            },
                        ], layout: {
                            title: { text: "PWM Signal" },
                            height: 300,
                        } }), _jsx(Button, { type: "primary", icon: _jsx(DownloadOutlined, {}), block: true, style: { marginTop: 16 }, onClick: downloadCSV, children: "Export CSV" })] })), _jsx(Modal, { open: isModalOpen, title: "Batch Add PWM Channels", onCancel: () => setIsModalOpen(false), onOk: () => {
                    batchForm.submit();
                }, children: _jsxs(Form, { form: batchForm, layout: "vertical", onFinish: (values) => {
                        const { baseFreq, multiples, amplitude, coefficient, prefix, } = values;
                        const newChannels = [];
                        for (let i = 1; i <= multiples; i++) {
                            newChannels.push({
                                name: `${prefix || "Ch"} ${i}`,
                                frequency: baseFreq * i,
                                amplitude,
                                coefficient,
                                enabled: true,
                            });
                        }
                        setChannels([...channels, ...newChannels]);
                        setIsModalOpen(false);
                        message.success(`${multiples} channels added!`);
                    }, initialValues: {
                        baseFreq: 875,
                        multiples: 5,
                        amplitude: 10,
                        coefficient: 8,
                        prefix: "Ch",
                    }, children: [_jsx(Form.Item, { label: "Base Frequency (Hz)", name: "baseFreq", rules: [{ required: true }], children: _jsx(InputNumber, { style: { width: "100%" }, min: 1, step: 1 }) }), _jsx(Form.Item, { label: "Multiples N", name: "multiples", rules: [{ required: true }], children: _jsx(InputNumber, { style: { width: "100%" }, min: 1, step: 1 }) }), _jsx(Form.Item, { label: "Amplitude", name: "amplitude", rules: [{ required: true }], children: _jsx(InputNumber, { style: { width: "100%" }, min: 0.1, step: 0.1 }) }), _jsx(Form.Item, { label: "Coefficient", name: "coefficient", rules: [{ required: true }], children: _jsx(InputNumber, { style: { width: "100%" }, min: 0.1, step: 0.1 }) }), _jsx(Form.Item, { label: "Channel Name Prefix", name: "prefix", children: _jsx(Input, { style: { width: "100%" } }) })] }) })] }));
};
export default PWMGenerator;
