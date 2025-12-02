import React, { useRef, useState, useEffect } from 'react';
import { Canvas, useFrame } from '@react-three/fiber';
import { OrbitControls } from '@react-three/drei';
import { Slider, Typography, Row, Col, Card, Button, Space, Progress } from 'antd';
import { Line } from '@ant-design/plots';

const { Title, Paragraph } = Typography;

const gravity = 9.81;
const floorY = 0;

interface BallProps {
  contactStiffness: number;
  mass: number;
  initialVelocity: number;
  dt: number;
  initialHeight: number;
  running: boolean;
  onRecord: (time: number, y: number) => void;
}

const Ball: React.FC<BallProps> = ({
  contactStiffness,
  mass,
  initialVelocity,
  dt,
  initialHeight,
  running,
  onRecord,
}) => {
  const meshRef = useRef<any>(null);
  const [positionY, setPositionY] = useState(initialHeight);
  const [velocity, setVelocity] = useState(initialVelocity);
  const [time, setTime] = useState(0);

  const physicsStepTarget = 1 / 60;
  let accumulatedTime = 0;

  useEffect(() => {
    setPositionY(initialHeight);
    setVelocity(initialVelocity);
    setTime(0);
  }, [initialHeight, running, initialVelocity]);

  useFrame((_, delta) => {
    if (!running) return;

    accumulatedTime += delta;

    let posY = positionY;
    let vel = velocity;
    let t = time;

    while (accumulatedTime >= physicsStepTarget) {
      const numSteps = Math.floor(physicsStepTarget / dt);

      for (let i = 0; i < numSteps; i++) {
        let penetrationDepth = 0;
        let force = 0;

        if (posY <= floorY) {
          penetrationDepth = floorY - posY;
          force = contactStiffness * penetrationDepth;
          const acc = (force / mass) - gravity;
          vel += acc * dt;
        } else {
          vel += -gravity * dt;
        }

        posY += vel * dt;
        t += dt;
      }

      accumulatedTime -= physicsStepTarget;
    }

    onRecord(t, posY);

    setPositionY(posY);
    setVelocity(vel);
    setTime(t);

    if (meshRef.current) {
      meshRef.current.position.y = posY;
    }
  });

  return (
    <>
      {/* @ts-ignore */}
      <mesh ref={meshRef}>
        {/* @ts-ignore */}
        <sphereGeometry args={[0.5, 32, 32]} />
        {/* @ts-ignore */}
        <meshStandardMaterial
          color={positionY < floorY ? 'red' : 'orange'}
          opacity={0.8}
          transparent
        />
      {/* @ts-ignore */}
      </mesh>
      {/* @ts-ignore */}
      <mesh rotation={[-Math.PI / 2, 0, 0]} position={[0, 0, 0]}>
        {/* @ts-ignore */}
        <planeGeometry args={[10, 10]} />
        {/* @ts-ignore */}
        <meshStandardMaterial color="lightgray" />
      {/* @ts-ignore */}
      </mesh>
    </>
  );
};

const ContactStiffnessDemoComponent: React.FC = () => {
  const [contactStiffness, setContactStiffness] = useState(1e4);
  const [mass, setMass] = useState(1);
  const [dt, setDt] = useState(0.001);
  const [initialHeight, setInitialHeight] = useState(5);
  const [running, setRunning] = useState(false);

  // 추가된 state
  const [youngsModulus, setYoungsModulus] = useState(210000); // MPa
  const [hMin, setHMin] = useState(1); // mm
  const [contactArea, setContactArea] = useState(100); // mm²
  const [alphaFactor, setAlphaFactor] = useState(0.5);

  // System dt 관련 state
  const [hSys, setHSys] = useState(0.1); // mm
  const [eSys, setESys] = useState(210000); // MPa
  const [rhoSys, setRhoSys] = useState(7800); // kg/m³

  const [data, setData] = useState<{ time: number; y: number }[]>([]);

  // Δt 안정 조건
  const omegaMax = Math.sqrt(contactStiffness / mass);
  const stableDt = 2 / omegaMax;

  // Mesh stiffness 계산
  const meshStiffness =
    (youngsModulus * contactArea) / hMin * 1e6; // N/m

  const ratio = contactStiffness / meshStiffness;

  // dt 기반 stiffness 한도
  const kMaxByDt = (4 * mass) / (dt * dt);

  // System wave speed
  const cSys = Math.sqrt((eSys * 1e6) / rhoSys); // m/s
  const dtSystem = (hSys * 1e-3) / cSys; // s

  const kMaxBySystemDt = (4 * mass) / (dtSystem * dtSystem);

  const effectiveContactStiffness = Math.min(
    contactStiffness,
    kMaxByDt,
    kMaxBySystemDt
  );

  const handleStart = () => {
    setData([]);
    setRunning(true);
  };

  const handleStop = () => {
    setRunning(false);
  };

  const handleReset = () => {
    setRunning(false);
    setData([]);
  };

  const handleRecord = (time: number, y: number) => {
    if (Math.floor(time * 30) % 30 === 0) {
      setData((prev) => [...prev, { time, y }]);
    }
  };

  const handleApplyRecommended = () => {
    const kContact =
      (alphaFactor * youngsModulus * contactArea) / hMin * 1e6;
    setContactStiffness(kContact);
  };

  const config = {
    data,
    xField: 'time',
    yField: 'y',
    height: 300,
    smooth: true,
    lineStyle: { stroke: '#ff7300', lineWidth: 2 },
    yAxis: {
      min: -1,
      title: { text: 'Height (m)' },
    },
    xAxis: {
      title: { text: 'Time (s)' },
    },
  };

  return (
    <Row gutter={16}>
      <Col span={12}>
        <Canvas camera={{ position: [0, 5, 10], fov: 50 }}>
          {/* @ts-ignore */}
          <ambientLight />
          {/* @ts-ignore */}
          <pointLight position={[10, 10, 10]} />
          <Ball
            contactStiffness={effectiveContactStiffness}
            mass={mass}
            initialVelocity={0}
            dt={dt}
            initialHeight={initialHeight}
            running={running}
            onRecord={handleRecord}
          />
          <OrbitControls />
        </Canvas>
      </Col>
      <Col span={12}>
        <Card>
          <Title level={4}>Contact Stiffness Demo</Title>
          <Space direction="vertical" style={{ width: '100%' }}>
            <Paragraph>
              <b>Initial Height:</b> {initialHeight.toFixed(2)} m
            </Paragraph>
            <Slider
              min={0.5}
              max={10}
              step={0.1}
              value={initialHeight}
              onChange={setInitialHeight}
            />

            <Paragraph>
              <b>Young’s Modulus:</b> {youngsModulus.toExponential(2)} MPa
            </Paragraph>
            <Slider
              min={100}
              max={500000}
              step={100}
              value={youngsModulus}
              onChange={setYoungsModulus}
            />

            <Paragraph>
              <b>h_min (Element Size):</b> {hMin.toFixed(2)} mm
            </Paragraph>
            <Slider
              min={0.1}
              max={10}
              step={0.1}
              value={hMin}
              onChange={setHMin}
            />

            <Paragraph>
              <b>Contact Area:</b> {contactArea.toFixed(2)} mm²
            </Paragraph>
            <Slider
              min={1}
              max={1000}
              step={1}
              value={contactArea}
              onChange={setContactArea}
            />

            <Paragraph>
              <b>Alpha Factor:</b> {alphaFactor.toFixed(2)}
            </Paragraph>
            <Slider
              min={0.1}
              max={1}
              step={0.1}
              value={alphaFactor}
              onChange={setAlphaFactor}
            />

            <Button onClick={handleApplyRecommended}>
              Apply Recommended Stiffness
            </Button>

            <Paragraph>
              <b>Recommended Contact Stiffness:</b>{" "}
              {(
                (alphaFactor * youngsModulus * contactArea) /
                hMin *
                1e6
              ).toExponential(2)} N/m
            </Paragraph>

            <Paragraph>
              <b>Contact Stiffness:</b> {contactStiffness.toExponential(2)} N/m
            </Paragraph>
            <Slider
              min={100}
              max={1e15}
              step={100}
              value={contactStiffness}
              onChange={setContactStiffness}
              tooltip={{ formatter: (v) => v?.toExponential(2) }}
            />

            <Paragraph>
              <b>Mesh Stiffness:</b> {meshStiffness.toExponential(2)} N/m
            </Paragraph>

            <Paragraph>
              <b>Contact / Mesh Stiffness Ratio:</b> {ratio.toFixed(2)}
            </Paragraph>

            <Progress
              percent={Math.min(ratio * 10, 100)}
              status={
                ratio < 2
                  ? "success"
                  : ratio < 10
                  ? "active"
                  : "exception"
              }
            />

            {ratio > 10 && (
              <Paragraph type="danger">
                ⚠️ Contact stiffness may be excessive vs mesh stiffness!
              </Paragraph>
            )}

            <Paragraph>
              <b>System Min Element Size:</b> {hSys.toFixed(3)} mm
            </Paragraph>
            <Slider
              min={0.01}
              max={10}
              step={0.01}
              value={hSys}
              onChange={setHSys}
            />

            <Paragraph>
              <b>System Young’s Modulus:</b> {eSys.toExponential(2)} MPa
            </Paragraph>
            <Slider
              min={100}
              max={500000}
              step={100}
              value={eSys}
              onChange={setESys}
            />

            <Paragraph>
              <b>System Density:</b> {rhoSys.toFixed(1)} kg/m³
            </Paragraph>
            <Slider
              min={1000}
              max={9000}
              step={100}
              value={rhoSys}
              onChange={setRhoSys}
            />

            <Paragraph>
              <b>Calculated System Δt:</b> {dtSystem.toExponential(2)} s
            </Paragraph>

            <Paragraph>
              <b>Max Contact Stiffness allowed by System Δt:</b>{" "}
              {kMaxBySystemDt.toExponential(2)} N/m
            </Paragraph>

            <Paragraph>
              <b>Time Step (dt):</b> {dt.toExponential(2)} s
            </Paragraph>
            <Slider
              min={1e-9}
              max={1e-2}
              step={1e-5}
              value={dt}
              onChange={setDt}
              tooltip={{ formatter: (v) => v?.toExponential(2) }}
            />

            <Paragraph>
              <b>Δt Stability Limit:</b> {stableDt.toExponential(2)} s
            </Paragraph>
            <Paragraph>
              <b>Max Contact Stiffness allowed by dt:</b>{" "}
              {kMaxByDt.toExponential(2)} N/m
            </Paragraph>
            <Paragraph>
              <b>Effective Contact Stiffness used:</b>{" "}
              {effectiveContactStiffness.toExponential(2)} N/m
            </Paragraph>
            <Paragraph type={
              contactStiffness > kMaxBySystemDt ? 'danger' : undefined
            }>
              {contactStiffness > kMaxBySystemDt
                ? '⚠️ Contact stiffness exceeds system dt limit! Auto-reduced.'
                : '✔️ Contact stiffness is OK for system dt.'}
            </Paragraph>

            <Space>
              <Button type="primary" onClick={handleStart} disabled={running}>
                ▶️ Start
              </Button>
              <Button onClick={handleStop} disabled={!running}>
                ⏸️ Stop
              </Button>
              <Button onClick={handleReset}>🔄 Reset</Button>
            </Space>

            <Title level={5}>Height vs Time</Title>
            <Line {...config} />
          </Space>
        </Card>
      </Col>
    </Row>
  );
};

export default ContactStiffnessDemoComponent;
