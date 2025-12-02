import React, { useState, useMemo } from 'react';
import {
  Form,
  InputNumber,
  Button,
  Select,
  Table,
  Typography,
  Card,
  Row,
  Col,
  Divider,
  Space,
} from 'antd';
import Plot from 'react-plotly.js';
import { MathJax, MathJaxContext } from 'better-react-mathjax';
import { Canvas, useFrame } from '@react-three/fiber';
import { OrbitControls } from '@react-three/drei';
import { extend } from '@react-three/fiber';
import * as THREE from 'three';

extend(THREE);

const { Title, Paragraph, Text } = Typography;

interface PronyTerm {
  tau: number;
  g: number;
}

const ViscoCube = ({
  scaleVector,
  shearStrain,
  position = [0, 0, 0],
  color = 'orange',
}: any) => {
  const ref = React.useRef<THREE.Mesh>(null);

  useFrame(() => {
    if (ref.current) {
      const magnify = 50;
      const γ = shearStrain * magnify;

      const matrix = new THREE.Matrix4();
      matrix.set(
        1, γ, 0, 0,
        0, 1, 0, 0,
        0, 0, 1, 0,
        0, 0, 0, 1
      );

      const scaleMatrix = new THREE.Matrix4().makeScale(
        scaleVector[0],
        scaleVector[1],
        scaleVector[2]
      );
      matrix.multiply(scaleMatrix);

      ref.current.matrixAutoUpdate = false;
      ref.current.matrix.copy(matrix);
    }
  });

  return React.createElement('mesh', { ref, position }, 
    React.createElement('boxGeometry', { args: [1, 1, 1] }),
    React.createElement('meshStandardMaterial', { color, wireframe: true })
  );
};

const ViscoElasticVisualizer: React.FC = () => {
  const [model, setModel] = useState<'prony' | 'simple'>('prony');
  const [bulkModulus, setBulkModulus] = useState(1000);
  const [strainRate, setStrainRate] = useState(0.1);
  const [compareStress, setCompareStress] = useState(5);

  const [pronyTerms, setPronyTerms] = useState<PronyTerm[]>([
    { tau: 0.01, g: 500 },
    { tau: 0.1, g: 300 },
    { tau: 1, g: 200 },
  ]);
  const [simpleParams, setSimpleParams] = useState({
    g0: 1000,
    gInf: 100,
    tau: 0.5,
  });
  const [G_inf, setGInf] = useState(100);

  const omegaRange = useMemo(() => {
    return Array.from({ length: 100 }, (_, i) => 10 ** (-1 + i * 4 / 99));
  }, []);

  const calcModuli = () => {
    const Gp: number[] = [];
    const Gpp: number[] = [];
    const Gabs: number[] = [];
    const tanDelta: number[] = [];

    omegaRange.forEach((omega) => {
      let Gstar = new mathComplex(0, 0);

      if (model === 'prony') {
        Gstar = Gstar.addScalar(G_inf);
        pronyTerms.forEach(({ tau, g }) => {
          const jwTau = new mathComplex(0, omega * tau);
          const term = jwTau.div(new mathComplex(1, omega * tau));
          Gstar = Gstar.add(term.mulScalar(g));
        });
      } else {
        const { g0, gInf, tau } = simpleParams;
        const jwTau = new mathComplex(0, omega * tau);
        const term = jwTau.div(new mathComplex(1, omega * tau));
        Gstar = term.mulScalar(g0 - gInf).addScalar(gInf);
      }
      Gp.push(Gstar.re);
      Gpp.push(Gstar.im);
      Gabs.push(Math.sqrt(Gstar.re ** 2 + Gstar.im ** 2));
      tanDelta.push(Gstar.im / (Gstar.re || 1e-6));
    });

    return { Gp, Gpp, Gabs, tanDelta };
  };

  const { Gp, Gpp, Gabs, tanDelta } = useMemo(calcModuli, [
    model,
    pronyTerms,
    simpleParams,
    omegaRange,
  ]);

  const relaxationData = useMemo(() => {
    const times = Array.from({ length: 100 }, (_, i) => 10 ** (-3 + i * 5 / 99));
    const Gt: number[] = [];
    const Jt: number[] = [];

    times.forEach((t) => {
      let G = 0;
      let J = 0;

      if (model === 'prony') {
        G = G_inf + pronyTerms.reduce(
          (acc, { tau, g }) => acc + g * Math.exp(-t / tau),
          0
        );

        J = (1 / G_inf) + pronyTerms.reduce(
          (acc, { tau, g }) =>
            acc + (g / G_inf) * (1 - Math.exp(-t / tau)),
          0
        );
      } else {
        const { g0, gInf, tau } = simpleParams;
        G = gInf + (g0 - gInf) * Math.exp(-t / tau);
        J = (1 / gInf) + ((g0 - gInf) / gInf) * (1 - Math.exp(-t / tau));
      }

      Gt.push(G);
      Jt.push(J);
    });

    return { times, Gt, Jt };
  }, [model, pronyTerms, simpleParams, G_inf]);

  const omegaIndex = 50;
  const GstarMid = Gabs[omegaIndex] || G_inf || 1;

  const poissonRatio = useMemo(() => {
    const G = GstarMid;
    const K = bulkModulus;
    return (3 * K - 2 * G) / (2 * (3 * K + G));
  }, [GstarMid, bulkModulus]);

  const elasticModulus = useMemo(() => {
    const G = GstarMid;
    const K = bulkModulus;
    return (9 * K * G) / (3 * K + G);
  }, [GstarMid, bulkModulus]);

  const compressiveStrain = useMemo(() => {
    return -compareStress / elasticModulus;
  }, [compareStress, elasticModulus]);

  const lateralStrain = useMemo(() => {
    return -compressiveStrain * poissonRatio;
  }, [compressiveStrain, poissonRatio]);

  const compressionScale = useMemo(() => {
    return [
      1 + compressiveStrain,
      1 + lateralStrain,
      1 + lateralStrain,
    ];
  }, [compressiveStrain, lateralStrain]);

  const omegaStrainRate = strainRate; // rad/s 로 가정
    const GstarForStrainRate = useMemo(() => {
    let Gstar = new mathComplex(0, 0);
    if (model === 'prony') {
        Gstar = Gstar.addScalar(G_inf);
        pronyTerms.forEach(({ tau, g }) => {
        const jwTau = new mathComplex(0, omegaStrainRate * tau);
        const term = jwTau.div(new mathComplex(1, omegaStrainRate * tau));
        Gstar = Gstar.add(term.mulScalar(g));
        });
    } else {
        const { g0, gInf, tau } = simpleParams;
        const jwTau = new mathComplex(0, omegaStrainRate * tau);
        const term = jwTau.div(new mathComplex(1, omegaStrainRate * tau));
        Gstar = term.mulScalar(g0 - gInf).addScalar(gInf);
    }
    return Math.sqrt(Gstar.re ** 2 + Gstar.im ** 2);
    }, [model, pronyTerms, simpleParams, G_inf, omegaStrainRate]);

    const shearStrainCompare = useMemo(() => {
    return compareStress / (GstarForStrainRate || 1);
    }, [compareStress, GstarForStrainRate]);

    return (
        <MathJaxContext>
          <div style={{ padding: 24 }}>
            <Title>Viscoelastic Visualizer</Title>
            <Divider />
            <Row gutter={24}>
              {/* Left Column */}
              <Col span={8}>
                <Card title="Material Parameters" bordered={false}>
                  <Form layout="vertical">
                    <Form.Item label="Model">
                      <Select value={model} onChange={(val) => setModel(val)}>
                        <Select.Option value="prony">Prony Series</Select.Option>
                        <Select.Option value="simple">Simple Viscoelasticity</Select.Option>
                      </Select>
                    </Form.Item>
      
                    {model === 'simple' && (
                      <>
                        <Form.Item label="G0 (MPa)">
                          <InputNumber
                            style={{ width: '100%' }}
                            value={simpleParams.g0}
                            onChange={(v) =>
                              setSimpleParams({ ...simpleParams, g0: v! })
                            }
                          />
                        </Form.Item>
                        <Form.Item label="G_inf (MPa)">
                          <InputNumber
                            style={{ width: '100%' }}
                            value={simpleParams.gInf}
                            onChange={(v) =>
                              setSimpleParams({ ...simpleParams, gInf: v! })
                            }
                          />
                        </Form.Item>
                        <Form.Item label="Tau (s)">
                          <InputNumber
                            style={{ width: '100%' }}
                            value={simpleParams.tau}
                            onChange={(v) =>
                              setSimpleParams({ ...simpleParams, tau: v! })
                            }
                          />
                        </Form.Item>
                      </>
                    )}
      
                    {model === 'prony' && (
                      <>
                        <Form.Item label="G_inf (MPa)">
                          <InputNumber
                            style={{ width: '100%' }}
                            value={G_inf}
                            onChange={(v) => setGInf(v!)}
                          />
                        </Form.Item>
                        <Form.Item label="Prony Terms">
                          <Table
                            size="small"
                            bordered
                            dataSource={pronyTerms.map((t, i) => ({
                              ...t,
                              key: i,
                            }))}
                            columns={[
                              {
                                title: 'Tau (s)',
                                dataIndex: 'tau',
                                render: (_, record, index) => (
                                  <InputNumber
                                    value={record.tau}
                                    onChange={(v) => {
                                      const updated = [...pronyTerms];
                                      updated[index].tau = v!;
                                      setPronyTerms(updated);
                                    }}
                                  />
                                ),
                              },
                              {
                                title: 'g (MPa)',
                                dataIndex: 'g',
                                render: (_, record, index) => (
                                  <InputNumber
                                    value={record.g}
                                    onChange={(v) => {
                                      const updated = [...pronyTerms];
                                      updated[index].g = v!;
                                      setPronyTerms(updated);
                                    }}
                                  />
                                ),
                              },
                            ]}
                            pagination={false}
                          />
                          <Button
                            style={{ marginTop: 8 }}
                            block
                            onClick={() =>
                              setPronyTerms([...pronyTerms, { tau: 0.1, g: 100 }])
                            }
                          >
                            Add Prony Term
                          </Button>
                        </Form.Item>
                      </>
                    )}
      
                    <Form.Item label="Bulk Modulus (MPa)">
                      <InputNumber
                        style={{ width: '100%' }}
                        value={bulkModulus}
                        onChange={(v) => setBulkModulus(v!)}
                      />
                    </Form.Item>
                  </Form>
                </Card>
      
                <Divider />
      
                <Card title="Equations" size="small" bordered={false}>
                  <Space direction="vertical" style={{ width: '100%' }}>
                    <Paragraph>
                      <MathJax>
                        {`\\[
                        G^*(\\omega) = G_{\\infty} + \\sum_{i=1}^{n}
                        \\frac{ g_i j \\omega \\tau_i }
                        { 1 + j \\omega \\tau_i }
                        \\]`}
                      </MathJax>
                      복소 전단 탄성률
                    </Paragraph>
                    <Paragraph>
                      <MathJax>{`\\[
                      G'(\\omega) = \\Re\\left( G^*(\\omega) \\right)
                      \\]`}</MathJax>
                      저장 탄성률
                    </Paragraph>
                    <Paragraph>
                      <MathJax>{`\\[
                      G''(\\omega) = \\Im\\left( G^*(\\omega) \\right)
                      \\]`}</MathJax>
                      손실 탄성률
                    </Paragraph>
                    <Paragraph>
                      <MathJax>{`\\[
                      |G^*(\\omega)| = \\sqrt{ G'^2 + G''^2 }
                      \\]`}</MathJax>
                      복소 탄성률의 크기
                    </Paragraph>
                    <Paragraph>
                      <MathJax>{`\\[
                      \\tan \\delta = \\frac{ G'' }{ G' }
                      \\]`}</MathJax>
                      손실 탄젠트
                    </Paragraph>
                    <Paragraph>
                      <MathJax>{`\\[
                      G(t) = G_{\\infty} + \\sum_{i=1}^{n}
                      g_i e^{- t / \\tau_i }
                      \\]`}</MathJax>
                      응력 이완
                    </Paragraph>
                    <Paragraph>
                      <MathJax>{`\\[
                      J(t) = \\frac{1}{G_{\\infty}} +
                      \\sum_{i=1}^{n} \\frac{g_i}{G_{\\infty}}
                      (1 - e^{-t/\\tau_i})
                      \\]`}</MathJax>
                      크리프 컴플라이언스
                    </Paragraph>
                    <Paragraph>
                      <MathJax>{`\\[
                      \\nu = \\frac{3K - 2G}{2(3K + G)}
                      \\]`}</MathJax>
                      푸아송비
                    </Paragraph>
                    <Paragraph>
                      <MathJax>{`\\[
                      \\varepsilon_{xx} = -\\frac{\\sigma}{E}
                      \\]`}</MathJax>
                      단축 압축 변형률
                    </Paragraph>
                    <Paragraph>
                      <MathJax>{`\\[
                      \\varepsilon_{yy} = \\varepsilon_{zz} = \\nu \\cdot \\frac{\\sigma}{E}
                      \\]`}</MathJax>
                      측변 인장 변형률
                    </Paragraph>
                    <Paragraph>
                      <MathJax>{`\\[
                      \\gamma = \\frac{\\tau}{|G^*(\\omega)|}
                      \\]`}</MathJax>
                      전단 변형률
                    </Paragraph>
                  </Space>
                </Card>
              </Col>
      
              {/* Right Column */}
              <Col span={16}>
              <Card title="Frequency Domain (Storage/Loss/Complex Moduli)" bordered={false}>
                <Plot
                    data={[
                    { x: omegaRange, y: Gp, name: 'G′ (Storage Modulus)', type: 'scatter', mode: 'lines' },
                    { x: omegaRange, y: Gpp, name: 'G″ (Loss Modulus)', type: 'scatter', mode: 'lines' },
                    { x: omegaRange, y: Gabs, name: '|G*| (Complex Modulus)', type: 'scatter', mode: 'lines' },
                    ]}
                    layout={{
                    xaxis: {
                        type: 'log',
                        title: { text: 'Angular Frequency ω [rad/s]', font: { size: 16 } },
                    },
                    yaxis: {
                        title: { text: 'Modulus [MPa]', font: { size: 16 } },
                    },
                    height: 400,
                    legend: {
                        orientation: 'h',
                        y: 1.15,
                    },
                    margin: { t: 50, b: 70, l: 60, r: 30 },
                    } as any}
                    useResizeHandler
                    style={{ width: '100%', height: '100%' }}
                />
                </Card>



      
                <Divider />
      
                <Card title="Loss Tangent" bordered={false}>
                <Plot
                    data={[
                    { x: omegaRange, y: tanDelta, name: 'tanδ', type: 'scatter', mode: 'lines' },
                    ]}
                    layout={{
                    xaxis: {
                        type: 'log',
                        title: { text: 'Angular Frequency ω [rad/s]', font: { size: 16 } },
                    },
                    yaxis: {
                        title: { text: 'tanδ [unitless]', font: { size: 16 } },
                        type: 'log',
                    },
                    height: 400,
                    legend: { orientation: 'h' },
                    margin: { t: 30, b: 50, l: 60, r: 30 },
                    } as any}
                    useResizeHandler
                    style={{ width: '100%', height: '100%' }}
                />
                </Card>


      
                <Divider />
      
                <Card title="Time Domain (Relaxation & Creep)" bordered={false}>
                    <Plot
                        data={[
                        {
                            x: relaxationData.times,
                            y: relaxationData.Gt,
                            name: 'G(t) (Relaxation Modulus)',
                            type: 'scatter',
                            mode: 'lines'
                        },
                        {
                            x: relaxationData.times,
                            y: relaxationData.Jt,
                            name: 'J(t) (Creep Compliance)',
                            type: 'scatter',
                            mode: 'lines'
                        },
                        ]}
                        layout={{
                        xaxis: {
                            type: 'log',
                            title: { text: 'Time [s]', font: { size: 16 } },
                        },
                        yaxis: {
                            title: { text: 'Modulus [MPa] / Compliance [1/MPa]', font: { size: 16 } },
                        },
                        height: 400,
                        legend: {
                            orientation: 'h',
                            y: 1.15,
                        },
                        margin: { t: 50, b: 70, l: 60, r: 30 },
                        } as any}
                        useResizeHandler
                        style={{ width: '100%', height: '100%' }}
                    />
                    </Card>



      
                <Divider />
      
                <Card title="Cube Controls" bordered={false}>
                  <Form layout="vertical">
                    <Form.Item label="Stress (MPa)">
                      <InputNumber
                        style={{ width: '100%' }}
                        value={compareStress}
                        onChange={(v) => setCompareStress(v!)}
                      />
                    </Form.Item>
                    <Form.Item label="Strain Rate (1/s)">
                      <InputNumber
                        style={{ width: '100%' }}
                        value={strainRate}
                        onChange={(v) => setStrainRate(v!)}
                      />
                    </Form.Item>
                  </Form>
                </Card>
      
                <Divider />
      
                <Card title="3D Cube Visualization" bordered={false}>
                  <div style={{ height: 400 }}>
                    <Canvas camera={{ position: [5, 3, 5] }}>
                      {/* @ts-ignore */}
                      <ambientLight />
                      {/* @ts-ignore */}
                      <directionalLight position={[5, 5, 5]} />
                      <OrbitControls />
                      {/* @ts-ignore */}
                      <axesHelper args={[2]} />
      
                      {/* Compression Cube */}
                      <ViscoCube
                        position={[-2, 0, 0]}
                        scaleVector={compressionScale}
                        shearStrain={0}
                        color="blue"
                      />
      
                      {/* Shear Cube */}
                      <ViscoCube
                        position={[2, 0, 0]}
                        scaleVector={[1, 1, 1]}
                        shearStrain={shearStrainCompare}
                        color="red"
                      />
                    </Canvas>
                  </div>
                  <Paragraph>
                    <Text strong>Compression strain x:</Text> {compressiveStrain.toExponential(3)}<br />
                    <Text strong>Lateral strain y/z:</Text> {lateralStrain.toExponential(3)}<br />
                    <Text strong>Shear strain:</Text> {shearStrainCompare.toExponential(3)}
                  </Paragraph>
                </Card>
      
              </Col>
            </Row>
          </div>
        </MathJaxContext>
      );
      
};

export default ViscoElasticVisualizer;

/** ---- Math Complex Class ---- **/
class mathComplex {
  re: number;
  im: number;
  constructor(re: number, im: number) {
    this.re = re;
    this.im = im;
  }
  add(other: mathComplex) {
    return new mathComplex(this.re + other.re, this.im + other.im);
  }
  addScalar(s: number) {
    return new mathComplex(this.re + s, this.im);
  }
  mulScalar(s: number) {
    return new mathComplex(this.re * s, this.im * s);
  }
  div(other: mathComplex) {
    const denom = other.re ** 2 + other.im ** 2;
    return new mathComplex(
      (this.re * other.re + this.im * other.im) / denom,
      (this.im * other.re - this.re * other.im) / denom
    );
  }
}
