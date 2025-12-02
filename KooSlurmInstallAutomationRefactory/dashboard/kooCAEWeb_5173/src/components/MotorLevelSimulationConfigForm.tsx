import React from "react";
import { MotorLevelSimulationConfig } from "../types/motorLevelSimulation";
import { Button, InputNumber, Form, Row, Col, Card } from "antd";

interface Props {
  onRun: (config: MotorLevelSimulationConfig) => void;
}

const MotorLevelSimulationConfigForm: React.FC<Props> = ({ onRun }) => {
  const [form] = Form.useForm();

  const defaultConfig: MotorLevelSimulationConfig = {
    r_P_global_0: [0.54667, 80.96126, -4.04957],
    r_Q_global: [10.0, 30.0, 0.0],
    xvector: [0.00827, 0.00453, 0.99996],
    yvector: [0.99986, 0.01476, -0.00833],
    zvector: [-0.01480, 0.99988, -0.00441],
    I_principal: [526.62083, 426.54252, 102.66056],
    m: 0.2018,
    mu: 0.4,
    g: 9.81,
    width: 77.856,
    height: 163.368,
    thickness: 7.94,
    dt: 0.001,
    duration: 0.1,
    freq: 157.0,
    F0: 350,
    gridX: 20,
    gridY: 20,
    forceDirection: [1,0.3,0],
  };

  const onFinish = (values: any) => {
    const merged: MotorLevelSimulationConfig = {
      ...defaultConfig,
      ...values,
      r_P_global_0: [
        values.r_P_global_0_0,
        values.r_P_global_0_1,
        values.r_P_global_0_2,
      ],
      r_Q_global: [
        values.r_Q_global_0,
        values.r_Q_global_1,
        values.r_Q_global_2,
      ],
      xvector: [
        values.xvector_0,
        values.xvector_1,
        values.xvector_2,
      ],
      yvector: [
        values.yvector_0,
        values.yvector_1,
        values.yvector_2,
      ],
      zvector: [
        values.zvector_0,
        values.zvector_1,
        values.zvector_2,
      ],
      I_principal: [
        values.I_principal_0,
        values.I_principal_1,
        values.I_principal_2,
      ],
      forceDirection: [
        values.forceDirection_0,
        values.forceDirection_1,
        values.forceDirection_2,
      ],
    };

    onRun(merged);
  };

  return (
    <Form
      layout="vertical"
      form={form}
      initialValues={{
        ...defaultConfig,
        r_P_global_0_0: defaultConfig.r_P_global_0[0],
        r_P_global_0_1: defaultConfig.r_P_global_0[1],
        r_P_global_0_2: defaultConfig.r_P_global_0[2],
        r_Q_global_0: defaultConfig.r_Q_global[0],
        r_Q_global_1: defaultConfig.r_Q_global[1],
        r_Q_global_2: defaultConfig.r_Q_global[2],
        xvector_0: defaultConfig.xvector[0],
        xvector_1: defaultConfig.xvector[1],
        xvector_2: defaultConfig.xvector[2],
        yvector_0: defaultConfig.yvector[0],
        yvector_1: defaultConfig.yvector[1],
        yvector_2: defaultConfig.yvector[2],
        zvector_0: defaultConfig.zvector[0],
        zvector_1: defaultConfig.zvector[1],
        zvector_2: defaultConfig.zvector[2],
        I_principal_0: defaultConfig.I_principal[0],
        I_principal_1: defaultConfig.I_principal[1],
        I_principal_2: defaultConfig.I_principal[2],
        forceDirection_0: 1,
        forceDirection_1: 0.3,
        forceDirection_2: 0,
      }}
      onFinish={onFinish}
    >
      <Card size="small" title="Simulation Settings" style={{ marginBottom: 16 }}>
        <Row gutter={16}>
          <Col span={12}>
            <Form.Item label="Duration (s)" name="duration">
              <InputNumber step={0.01} min={0.01} style={{ width: "100%" }} />
            </Form.Item>
          </Col>
          <Col span={12}>
            <Form.Item label="Time Step dt (s)" name="dt">
              <InputNumber step={0.0001} min={0.0001} style={{ width: "100%" }} />
            </Form.Item>
          </Col>
          <Col span={12}>
            <Form.Item label="Frequency (Hz)" name="freq">
              <InputNumber style={{ width: "100%" }} />
            </Form.Item>
          </Col>
          <Col span={12}>
            <Form.Item label="Force F0 (mN)" name="F0">
              <InputNumber style={{ width: "100%" }} />
            </Form.Item>
          </Col>
          <Col span={12}>
            <Form.Item label="Grid X" name="gridX">
              <InputNumber min={5} max={200} style={{ width: "100%" }} />
            </Form.Item>
          </Col>
          <Col span={12}>
            <Form.Item label="Grid Y" name="gridY">
              <InputNumber min={5} max={200} style={{ width: "100%" }} />
            </Form.Item>
          </Col>
        </Row>
      </Card>
      
      <Card size="small" title="Force Direction" style={{ marginBottom: 16 }}>
        <Row gutter={8}>
            {["X", "Y", "Z"].map((axis, i) => (
            <Col span={8} key={axis}>
                <Form.Item label={axis} name={`forceDirection_${i}`}>
                <InputNumber style={{ width: "100%" }} />
                </Form.Item>
            </Col>
            ))}
        </Row>
        </Card>
      <Card size="small" title="Geometry" style={{ marginBottom: 16 }}>
        <Row gutter={16}>
            <Col span={12}>
            <Form.Item label="Width (mm)" name="width">
                <InputNumber style={{ width: "100%" }} />
            </Form.Item>
            </Col>
            <Col span={12}>
            <Form.Item label="Height (mm)" name="height">
                <InputNumber style={{ width: "100%" }} />
            </Form.Item>
            </Col>
            <Col span={24}>
            <Form.Item label="Thickness (mm)" name="thickness">
                <InputNumber style={{ width: "100%" }} />
            </Form.Item>
            </Col>
        </Row>
        </Card>


      <Card size="small" title="Material Properties" style={{ marginBottom: 16 }}>
        <Row gutter={16}>
          <Col span={8}>
            <Form.Item label="Mass (kg)" name="m">
              <InputNumber style={{ width: "100%" }} />
            </Form.Item>
          </Col>
          <Col span={8}>
            <Form.Item label="μ (Friction)" name="mu">
              <InputNumber style={{ width: "100%" }} step={0.01} min={0} />
            </Form.Item>
          </Col>
          <Col span={8}>
            <Form.Item label="Gravity (m/s²)" name="g">
              <InputNumber style={{ width: "100%" }} step={0.01} min={0} />
            </Form.Item>
          </Col>
        </Row>
      </Card>

      <Card size="small" title="Position Vectors" style={{ marginBottom: 16 }}>
        <Row gutter={16}>
          <Col span={24}>
            <Form.Item label="P0 (X, Y, Z)">
              <Row gutter={8}>
                <Col span={8}>
                  <Form.Item name="r_P_global_0_0" noStyle>
                    <InputNumber style={{ width: "100%" }} />
                  </Form.Item>
                </Col>
                <Col span={8}>
                  <Form.Item name="r_P_global_0_1" noStyle>
                    <InputNumber style={{ width: "100%" }} />
                  </Form.Item>
                </Col>
                <Col span={8}>
                  <Form.Item name="r_P_global_0_2" noStyle>
                    <InputNumber style={{ width: "100%" }} />
                  </Form.Item>
                </Col>
              </Row>
            </Form.Item>
          </Col>
          <Col span={24}>
            <Form.Item label="Q (X, Y, Z)">
              <Row gutter={8}>
                <Col span={8}>
                  <Form.Item name="r_Q_global_0" noStyle>
                    <InputNumber style={{ width: "100%" }} />
                  </Form.Item>
                </Col>
                <Col span={8}>
                  <Form.Item name="r_Q_global_1" noStyle>
                    <InputNumber style={{ width: "100%" }} />
                  </Form.Item>
                </Col>
                <Col span={8}>
                  <Form.Item name="r_Q_global_2" noStyle>
                    <InputNumber style={{ width: "100%" }} />
                  </Form.Item>
                </Col>
              </Row>
            </Form.Item>
          </Col>
        </Row>
      </Card>

      <Card size="small" title="Vectors" style={{ marginBottom: 16 }}>
        {["xvector", "yvector", "zvector", "I_principal"].map((vector) => (
          <Row gutter={8} key={vector} style={{ marginBottom: 8 }}>
            <Col span={24}>
              <Form.Item label={`${vector} (X, Y, Z)`}>
                <Row gutter={8}>
                  <Col span={8}>
                    <Form.Item name={`${vector}_0`} noStyle>
                      <InputNumber style={{ width: "100%" }} />
                    </Form.Item>
                  </Col>
                  <Col span={8}>
                    <Form.Item name={`${vector}_1`} noStyle>
                      <InputNumber style={{ width: "100%" }} />
                    </Form.Item>
                  </Col>
                  <Col span={8}>
                    <Form.Item name={`${vector}_2`} noStyle>
                      <InputNumber style={{ width: "100%" }} />
                    </Form.Item>
                  </Col>
                </Row>
              </Form.Item>
            </Col>
          </Row>
        ))}
      </Card>

      <Button htmlType="submit" type="primary" block>
        Run Motor Level Simulation
      </Button>
    </Form>
  );
};

export default MotorLevelSimulationConfigForm;
