import React, { useState } from "react";
import {
  Form,
  InputNumber,
  Input,
  Button,
  Checkbox,
  Row,
  Col,
  Card,
  Table,
  Space,
  Popconfirm,
  message,
  Modal,
} from "antd";
import Plot from "react-plotly.js";
import { generatePWM } from "../utils/pwmGenerator";
import { PWMConfig, PWMChannel } from "../types/pwm";
import { DownloadOutlined, PlusOutlined } from "@ant-design/icons";

interface PWMGeneratorProps {
  onPWMGenerated?: (result: {
    channelName: string;
    duration: number;
    dt: number;
    t: number[];
    PWM: number[];
  }) => void;
}

const PWMGenerator: React.FC<PWMGeneratorProps> = ({ onPWMGenerated }) => {
  const [form] = Form.useForm();
  const [channels, setChannels] = useState<PWMChannel[]>([
    {
      name: "Channel 1",
      frequency: 875,
      amplitude: 10,
      coefficient: 8,
      enabled: true,
    },
  ]);

  const [plotData, setPlotData] = useState<any>(null);
  const [isModalOpen, setIsModalOpen] = useState(false);
  const [batchForm] = Form.useForm();

  const handleAddChannel = () => {
    const newChannel: PWMChannel = {
      name: `Channel ${channels.length + 1}`,
      frequency: 1000,
      amplitude: 10,
      coefficient: 8,
      enabled: true,
    };
    setChannels([...channels, newChannel]);
  };

  const handleDeleteChannel = (index: number) => {
    const newChannels = [...channels];
    newChannels.splice(index, 1);
    setChannels(newChannels);
  };

  const handleChannelChange = (
    index: number,
    key: keyof PWMChannel,
    value: PWMChannel[keyof PWMChannel]
  ) => {
    const newChannels = [...channels];
    (newChannels[index] as any)[key] = value;
    setChannels(newChannels);
  };

  const onFinish = (values: any) => {
    const config: PWMConfig = {
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
    if (!plotData) return;

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

  return (
    <Card title="PWM Generator" bordered>
      <Form
        layout="vertical"
        form={form}
        initialValues={{
          targetFrequency: 167.5,
          sinAmplitude: 10,
          dt: 0.00001,
          duration: 0.05,
        }}
        onFinish={onFinish}
      >
        <Row gutter={16}>
          <Col span={6}>
            <Form.Item label="Target Frequency (Hz)" name="targetFrequency">
              <InputNumber min={1} step={0.1} style={{ width: "100%" }} />
            </Form.Item>
          </Col>
          <Col span={6}>
            <Form.Item label="Sin Amplitude" name="sinAmplitude">
              <InputNumber min={0.1} step={0.1} style={{ width: "100%" }} />
            </Form.Item>
          </Col>
          <Col span={6}>
            <Form.Item label="dt (s)" name="dt">
              <InputNumber
                min={0.000001}
                step={0.000001}
                style={{ width: "100%" }}
              />
            </Form.Item>
          </Col>
          <Col span={6}>
            <Form.Item label="Duration (s)" name="duration">
              <InputNumber min={0.01} step={0.01} style={{ width: "100%" }} />
            </Form.Item>
          </Col>
        </Row>

        <Card size="small" title="PWM Channels" style={{ marginTop: 16 }}>
          <Button
            type="primary"
            style={{ marginBottom: 16 }}
            onClick={() => setIsModalOpen(true)}
          >
            Batch Add Channels
          </Button>
          <Table
            dataSource={channels}
            pagination={false}
            rowKey="name"
            columns={[
              {
                title: "Name",
                dataIndex: "name",
                render: (text, record, index) => (
                  <Input
                    value={text}
                    onChange={(e) =>
                      handleChannelChange(index, "name", e.target.value)
                    }
                  />
                ),
              },
              {
                title: "Frequency (Hz)",
                dataIndex: "frequency",
                render: (value, record, index) => (
                  <InputNumber
                    value={value}
                    min={1}
                    onChange={(v) =>
                      handleChannelChange(index, "frequency", v)
                    }
                  />
                ),
              },
              {
                title: "Amplitude",
                dataIndex: "amplitude",
                render: (value, record, index) => (
                  <InputNumber
                    value={value}
                    onChange={(v) =>
                      handleChannelChange(index, "amplitude", v)
                    }
                  />
                ),
              },
              {
                title: "Coefficient",
                dataIndex: "coefficient",
                render: (value, record, index) => (
                  <InputNumber
                    value={value}
                    onChange={(v) =>
                      handleChannelChange(index, "coefficient", v)
                    }
                  />
                ),
              },
              {
                title: "Enabled",
                dataIndex: "enabled",
                render: (value, record, index) => (
                  <Checkbox
                    checked={value}
                    onChange={(e) =>
                      handleChannelChange(index, "enabled", e.target.checked)
                    }
                  />
                ),
              },
              {
                title: "Actions",
                key: "actions",
                render: (_, record, index) => (
                  <Popconfirm
                    title="Delete this channel?"
                    onConfirm={() => handleDeleteChannel(index)}
                  >
                    <Button danger size="small">
                      Delete
                    </Button>
                  </Popconfirm>
                ),
              },
            ]}
          />
          <Button
            type="dashed"
            icon={<PlusOutlined />}
            style={{ marginTop: 12 }}
            onClick={handleAddChannel}
          >
            Add Channel
          </Button>
        </Card>

        <Button
          type="primary"
          htmlType="button"
          block
          style={{ marginTop: 16 }}
          onClick={() => {
            form.submit();
          }}
        >
          Generate PWM
        </Button>
      </Form>

      {plotData && (
        <>
          <Plot
            data={[
              {
                x: plotData.t,
                y: plotData.SinX,
                type: "scatter",
                mode: "lines",
                name: "Sin Wave",
              },
            ]}
            layout={{
              title: { text: "Sine Wave" },
              height: 300,
            }}
          />

          <Plot
            data={plotData.SawX.map((saw: number[], idx: number) => ({
              x: plotData.t,
              y: saw,
              type: "scatter",
              mode: "lines",
              name: `SawX[${idx}]`,
            }))}
            layout={{
              title: { text: "Sawtooth Waves" },
              height: 300,
            }}
          />

          <Plot
            data={[
              {
                x: plotData.t,
                y: plotData.PWM,
                type: "scatter",
                mode: "lines",
                name: "PWM",
              },
            ]}
            layout={{
              title: { text: "PWM Signal" },
              height: 300,
            }}
          />

          <Button
            type="primary"
            icon={<DownloadOutlined />}
            block
            style={{ marginTop: 16 }}
            onClick={downloadCSV}
          >
            Export CSV
          </Button>
        </>
      )}

      <Modal
        open={isModalOpen}
        title="Batch Add PWM Channels"
        onCancel={() => setIsModalOpen(false)}
        onOk={() => {
          batchForm.submit();
        }}
      >
        <Form
          form={batchForm}
          layout="vertical"
          onFinish={(values) => {
            const {
              baseFreq,
              multiples,
              amplitude,
              coefficient,
              prefix,
            } = values;
            const newChannels: PWMChannel[] = [];

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
          }}
          initialValues={{
            baseFreq: 875,
            multiples: 5,
            amplitude: 10,
            coefficient: 8,
            prefix: "Ch",
          }}
        >
          <Form.Item
            label="Base Frequency (Hz)"
            name="baseFreq"
            rules={[{ required: true }]}
          >
            <InputNumber style={{ width: "100%" }} min={1} step={1} />
          </Form.Item>
          <Form.Item
            label="Multiples N"
            name="multiples"
            rules={[{ required: true }]}
          >
            <InputNumber style={{ width: "100%" }} min={1} step={1} />
          </Form.Item>
          <Form.Item
            label="Amplitude"
            name="amplitude"
            rules={[{ required: true }]}
          >
            <InputNumber style={{ width: "100%" }} min={0.1} step={0.1} />
          </Form.Item>
          <Form.Item
            label="Coefficient"
            name="coefficient"
            rules={[{ required: true }]}
          >
            <InputNumber style={{ width: "100%" }} min={0.1} step={0.1} />
          </Form.Item>
          <Form.Item label="Channel Name Prefix" name="prefix">
            <Input style={{ width: "100%" }} />
          </Form.Item>
        </Form>
      </Modal>
    </Card>
  );
};

export default PWMGenerator;
