import React, { useState } from "react";
import {
  Card,
  Form,
  Select,
  Input,
  InputNumber,
  Button,
  Table,
  message,
  Space,
} from "antd";
import TextArea from "antd/es/input/TextArea";
import PWMGenerator from "../PWMGenerator";
import { MassNode } from "../../types/mck/modelTypes";
import { TransientForce } from "../../types/mck/transientTypes";

const { Option } = Select;

interface TransientAnalysisPanelProps {
  nodes: MassNode[];
  onAddForce: (force: TransientForce) => void;
  onRunTransient: () => void;
  onDeleteForce: (forceKey: string) => void;
  forces: TransientForce[];
}

const TransientAnalysisPanel: React.FC<TransientAnalysisPanelProps> = ({
  nodes,
  onAddForce,
  onRunTransient,
  onDeleteForce,
  forces,
}) => {
  const [inputType, setInputType] = useState<"function" | "pwm" | "table">(
    "function"
  );

  const [form] = Form.useForm();

  const handlePasteTable = (e: React.ClipboardEvent<HTMLTextAreaElement>) => {
    const pasted = e.clipboardData.getData("Text");
    const rows = pasted
      .trim()
      .split(/\r?\n/)
      .map((line) =>
        line
          .trim()
          .split(/[\t, ]+/)
          .map(Number)
      );

    const t: number[] = [];
    const f: number[] = [];

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

      let newForce: TransientForce;

      if (inputType === "function") {
        newForce = {
          nodeId: values.nodeId,
          type: "function",
          expression: values.expression,
          duration: values.duration,
          dt: values.dt,
        };
      } else if (inputType === "table" || inputType === "pwm") {
        newForce = {
          nodeId: values.nodeId,
          type: "table",
          timeArray: values.timeArray ?? [],
          forceArray: values.forceArray ?? [],
          duration: values.duration,
          dt: values.dt,
          pwmChannel: values.pwmChannel,
        };
      } else {
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
    } catch (err: any) {
      console.error("Validation failed", err);
      if (err?.errorFields) {
        err.errorFields.forEach((field: any) => {
          console.error(`Field ${field.name} - Errors:`, field.errors);
        });
      }
      message.error("Please check the form inputs.");
    }
  };

  const handleRunTransient = async () => {
    try {
      await onRunTransient();
    } catch (e) {
      console.error("Transient run error", e);
      message.error("Error during transient analysis.");
    }
  };

  const tableColumns = [
    { title: "Node", dataIndex: "nodeId" },
    { title: "Type", dataIndex: "type" },
    {
      title: "Expression / Data",
      render: (_: any, rec: TransientForce) => {
        if (rec.type === "function") {
          return rec.expression;
        } else if (rec.type === "table") {
          if (Array.isArray(rec.timeArray)) {
            return `${rec.timeArray.length} points`;
          } else {
            return "0 points";
          }
        } else {
          return rec.pwmChannel;
        }
      },
    },
    { title: "Duration", dataIndex: "duration" },
    {
      title: "Action",
      render: (_: any, rec: TransientForce) => {
        const key = `${rec.nodeId}-${rec.type}-${rec.expression || rec.pwmChannel || ""}`;
        return (
          <Button
            danger
            size="small"
            onClick={() => onDeleteForce(key)}
          >
            Delete
          </Button>
        );
      },
    },
  ];

  return (
    <Card size="small" title="Transient Analysis">
      <Space direction="vertical" style={{ width: "100%" }}>
        <Select
          value={inputType}
          onChange={(v) => setInputType(v)}
          style={{ width: 200 }}
        >
          <Option value="function">Function</Option>
          <Option value="pwm">PWM</Option>
          <Option value="table">Table</Option>
        </Select>

        <Form
          layout="vertical"
          form={form}
          initialValues={{
            nodeId: nodes[0]?.id || null,
            duration: 1,
            dt: 0.001,
            expression: "10*sin(2*pi*50*t)",
            timeArray: [],
            forceArray: [],
          }}
        >
          <Form.Item
            label="Target Node"
            name="nodeId"
            rules={[{ required: true }]}
          >
            <Select>
              {nodes.map((n) => (
                <Option key={n.id} value={n.id}>
                  {n.id}
                </Option>
              ))}
            </Select>
          </Form.Item>

          {inputType === "function" && (
            <>
              <Form.Item
                label="Expression"
                name="expression"
                rules={[{ required: true }]}
              >
                <Input placeholder="e.g. 10*sin(2*pi*50*t)" />
              </Form.Item>
              <Form.Item
                label="Duration (s)"
                name="duration"
                rules={[{ required: true }]}
              >
                <InputNumber
                  min={0.01}
                  step={0.01}
                  style={{ width: "100%" }}
                />
              </Form.Item>
              <Form.Item
                label="dt (s)"
                name="dt"
                rules={[{ required: true }]}
              >
                <InputNumber
                  min={0.000001}
                  step={0.000001}
                  style={{ width: "100%" }}
                />
              </Form.Item>
            </>
          )}

          {inputType === "table" && (
            <>
              <Form.Item label="Paste Time-Force Table">
                <TextArea
                  rows={4}
                  onPaste={handlePasteTable}
                  placeholder="Paste 2 columns here"
                />
              </Form.Item>

              <Form.Item shouldUpdate noStyle>
                {() => {
                  const values = form.getFieldsValue();
                  const timeArr = values.timeArray || [];
                  const forceArr = values.forceArray || [];

                  return timeArr.length > 0 ? (
                    <Table
                      size="small"
                      columns={[
                        { title: "Time", dataIndex: "time" },
                        { title: "Force", dataIndex: "force" },
                      ]}
                      dataSource={timeArr.map((t: number, i: number) => ({
                        key: i,
                        time: t,
                        force: forceArr[i],
                      }))}
                      pagination={false}
                      style={{ marginTop: 8 }}
                    />
                  ) : null;
                }}
              </Form.Item>

              <Form.Item
                label="Duration (s)"
                name="duration"
                rules={[{ required: true }]}
              >
                <InputNumber
                  min={0.01}
                  step={0.01}
                  style={{ width: "100%" }}
                />
              </Form.Item>
              <Form.Item
                label="dt (s)"
                name="dt"
                rules={[{ required: true }]}
              >
                <InputNumber
                  min={0.000001}
                  step={0.000001}
                  style={{ width: "100%" }}
                />
              </Form.Item>
            </>
          )}

          {inputType === "pwm" && (
            <>
              <PWMGenerator
                onPWMGenerated={(result) => {
                    onAddForce({
                    nodeId: form.getFieldValue("nodeId"),
                    type: "table",
                    timeArray: result.t,
                    forceArray: result.PWM,
                    duration: result.duration,
                    dt: result.dt,
                    pwmChannel: result.channelName,
                    });
                }}
                />

              
            </>
          )}
            {inputType !== "pwm" && (
          <Button type="primary" onClick={handleAddForce}>
            Add Force
          </Button>
            )}
        </Form>

        <Table
          size="small"
          columns={tableColumns}
          dataSource={forces || []}
          rowKey={(rec) =>
            `${rec.nodeId}-${rec.type}-${rec.expression || rec.pwmChannel || ""}`
          }
          pagination={false}
        />

        <Button type="primary" block onClick={handleRunTransient}>
          Run Transient Analysis
        </Button>
      </Space>
    </Card>
  );
};

export default TransientAnalysisPanel;
