import React, { useState, useEffect } from "react";
import {
  Form,
  InputNumber,
  Button,
  Descriptions,
  Divider,
  Typography,
  Row,
  Col,
  Card,
} from "antd";
import Plot from "react-plotly.js";
import { BlockMath, InlineMath } from "react-katex";
import "katex/dist/katex.min.css";

const { Title, Paragraph } = Typography;

const RambergOsgoodPanel: React.FC = () => {
  // -----------------------------
  // 상태
  // -----------------------------

  // Material props
  const [E, setE] = useState<number>(200); // GPa
  const [density, setDensity] = useState<number>(7.85); // g/cm³

  // Ramberg-Osgood params
  const [sigma0, setSigma0] = useState<number>(250); // MPa
  const [K, setK] = useState<number>(0.02);
  const [n, setN] = useState<number>(2.0);
  const [offsetStrainPct, setOffsetStrainPct] = useState<number>(0.2);

  // Fracture strain
  const [fractureStrain, setFractureStrain] = useState<number | null>(null);

  // Fatigue parameters
  const [sigmaFPrime, setSigmaFPrime] = useState<number | null>(null);
  const [b, setB] = useState<number | null>(null);
  const [epsilonFPrime, setEpsilonFPrime] = useState<number | null>(null);
  const [c, setC] = useState<number | null>(null);

  // Computed curve
  const [strainData, setStrainData] = useState<number[]>([]);
  const [stressData, setStressData] = useState<number[]>([]);

  // Fatigue curves
  const [snData, setSnData] = useState<any[]>([]);
  const [enData, setEnData] = useState<any[]>([]);

  const [sigma02, setSigma02] = useState<number | null>(null);
  const [sigmaMax, setSigmaMax] = useState<number | null>(null);

  // -----------------------------
  // 계산 함수들
  // -----------------------------

  const calcStrain = (sigma: number) => {
    const elastic = sigma / (E * 1e3);
    const plastic = K * Math.pow(sigma / sigma0, n);
    return elastic + plastic;
  };

  const calcSigma02 = () => {
    const epsOffset = offsetStrainPct / 100;
    const f = (sigma: number) => {
      return calcStrain(sigma) - (epsOffset + sigma / (E * 1e3));
    };

    let lower = 0;
    let upper = sigma0 * 5;
    let mid;
    for (let i = 0; i < 50; i++) {
      mid = (lower + upper) / 2;
      const val = f(mid);
      if (Math.abs(val) < 1e-6) break;
      if (val > 0) upper = mid;
      else lower = mid;
    }
    return mid!;
  };

  const generateCurve = () => {
    const stressArr: number[] = [];
    const strainArr: number[] = [];

    for (let sigma = 0; sigma <= sigma0 * 5; sigma += sigma0 * 5 / 500) {
      const eps = calcStrain(sigma);
      if (fractureStrain !== null && eps > fractureStrain) break;
      stressArr.push(sigma);
      strainArr.push(eps);
    }
    setStressData(stressArr);
    setStrainData(strainArr);
    setSigmaMax(Math.max(...stressArr));
  };

  const generateFatigueCurves = () => {
    if (
      sigmaFPrime === null ||
      b === null ||
      epsilonFPrime === null ||
      c === null
    ) {
      setSnData([]);
      setEnData([]);
      return;
    }

    const Ncycles = [];
    const stressAmplitude = [];
    const strainAmplitude = [];

    for (let logN = 3; logN <= 6; logN += 0.1) {
      const N = Math.pow(10, logN) / 2; // 2N_f
      const sa = sigmaFPrime * Math.pow(N, b);
      const ea = epsilonFPrime * Math.pow(N, c);

      Ncycles.push(N * 2);
      stressAmplitude.push(sa);
      strainAmplitude.push(ea);
    }

    setSnData([
      {
        x: Ncycles,
        y: stressAmplitude,
        mode: "lines+markers",
        name: "SN Curve",
      },
    ]);

    setEnData([
      {
        x: Ncycles,
        y: strainAmplitude,
        mode: "lines+markers",
        name: "ε-N Curve",
      },
    ]);
  };

  // -----------------------------
  // Hooks
  // -----------------------------

  useEffect(() => {
    const s02 = calcSigma02();
    setSigma02(s02);
    generateCurve();
  }, [E, sigma0, K, n, offsetStrainPct, fractureStrain]);

  useEffect(() => {
    generateFatigueCurves();
  }, [sigmaFPrime, b, epsilonFPrime, c]);

  // -----------------------------
  // Graph Click
  // -----------------------------

  const handleGraphClick = (e: any) => {
    const x = e.points?.[0]?.x;
    if (x !== undefined) {
      setFractureStrain(x/100);
      const newSigmaFPrime = sigma0 * 1.5;
      const newB = -0.08;
      const newEpsilonFPrime = 0.5 * x;
      const newC = -0.5;

      setSigmaFPrime(newSigmaFPrime);
      setB(newB);
      setEpsilonFPrime(newEpsilonFPrime);
      setC(newC);
    }
  };

  const resetFractureStrain = () => {
    setFractureStrain(null);
    setSigmaFPrime(null);
    setB(null);
    setEpsilonFPrime(null);
    setC(null);
  };

  const generateTotalStrainLifeCurve = () => {
    if (
      sigmaFPrime === null ||
      b === null ||
      epsilonFPrime === null ||
      c === null
    ) {
      return [];
    }
  
    const Ncycles = [];
    const totalStrainAmplitude = [];
  
    for (let logN = 3; logN <= 6; logN += 0.1) {
      const N = Math.pow(10, logN) / 2; // 2N_f
      const elasticStrain = (sigmaFPrime / (E * 1e3)) * Math.pow(N, b);
      const plasticStrain = epsilonFPrime * Math.pow(N, c);
      const total = elasticStrain + plasticStrain;
  
      Ncycles.push(N * 2);
      totalStrainAmplitude.push(total);
    }
  
    return [{
      x: Ncycles,
      y: totalStrainAmplitude,
      mode: "lines+markers",
      name: "Total Strain-Life Curve"
    }];
  };
  

  // -----------------------------
  // Render
  // -----------------------------

  return (
    <>
      <Title level={3}>Ramberg-Osgood Material Model</Title>

      <Paragraph>
        Ramberg-Osgood 모델은 금속 재료의 탄성-소성 거동을 표현하기 위해
        사용되며, 응력(<InlineMath math="\sigma"/>)과 변형률(<InlineMath math="\varepsilon"/>) 사이의
        비선형 관계를 나타냅니다.
      </Paragraph>
      <BlockMath
        math={String.raw`\varepsilon = \frac{\sigma}{E} + K \cdot \left(\frac{\sigma}{\sigma_0}\right)^n`}
      />

      <Row gutter={16}>
        <Col xs={24} md={12}>
          <Card title="Material Properties" size="small">
            <Form layout="vertical">
              <Form.Item label="Young's Modulus E (GPa)">
                <InputNumber
                  min={1}
                  value={E}
                  onChange={(value) => setE(value || 0)}
                  style={{ width: "100%" }}
                />
              </Form.Item>
              <Form.Item label="Density (g/cm³)">
                <InputNumber
                  min={0.1}
                  value={density}
                  onChange={(value) => setDensity(value || 0)}
                  style={{ width: "100%" }}
                />
              </Form.Item>
              <Form.Item label="Offset Yield Stress σ₀ (MPa)">
                <InputNumber
                  min={1}
                  value={sigma0}
                  onChange={(value) => setSigma0(value || 0)}
                  style={{ width: "100%" }}
                />
              </Form.Item>
            </Form>
          </Card>
        </Col>

        <Col xs={24} md={12}>
          <Card title="Ramberg-Osgood Parameters" size="small">
            <Form layout="vertical">
              <Form.Item label="Strength Coefficient K">
                <InputNumber
                  min={0.0001}
                  step={0.0001}
                  value={K}
                  onChange={(value) => setK(value || 0.0001)}
                  style={{ width: "100%" }}
                />
              </Form.Item>
              <Form.Item label="Strain Hardening Exponent n">
                <InputNumber
                  min={1}
                  step={0.01}
                  value={n}
                  onChange={(value) => setN(value || 1)}
                  style={{ width: "100%" }}
                />
              </Form.Item>
              <Form.Item label="Offset Strain (%)">
                <InputNumber
                  min={0.01}
                  max={1}
                  step={0.01}
                  value={offsetStrainPct}
                  onChange={(value) => setOffsetStrainPct(value || 0)}
                  style={{ width: "100%" }}
                />
              </Form.Item>
            </Form>
          </Card>
        </Col>
      </Row>

      <Divider />

      <Card
        title="Stress-Strain Curve"
        size="small"
        style={{ marginBottom: "24px" }}
        >
        <Plot
                      data={[
            {
              x: strainData.map((v) => v * 100),
              y: stressData,
              mode: "lines+markers",
              marker: { size: 4 },
              name: "Stress-Strain Curve",
            },
            ...(fractureStrain !== null
              ? [
                  {
                    x: [fractureStrain * 100, fractureStrain * 100],
                    y: [0, Math.max(...stressData)],
                    type: "scatter",
                    mode: "lines",
                    line: { color: "red", dash: "dot" },
                    name: "Fracture Strain",
                  },
                ]
              : []),
          ] as any}
          layout={{
            height: 500,
            autosize: true,
            title: "Stress-Strain Curve",
            margin: { l: 40, r: 20, t: 40, b: 40 },
            xaxis: { title: "Strain (%)", type: "linear" },
            yaxis: { title: "Stress (MPa)" },
          } as any}
            config={{
                responsive: true,
            }}
            useResizeHandler
            style={{ width: "100%", height: "100%" }}
            onClick={handleGraphClick}
        />

        <Button
            danger
            onClick={resetFractureStrain}
            style={{ marginTop: "10px", marginBottom: "10px" }}
        >
            Fracture Strain 초기화
        </Button>
        </Card>

      <Divider />

      <Card title="Calculated Properties" size="small">
        <Descriptions bordered column={1}>
          <Descriptions.Item label="Offset Yield Strength σ₀.₂">
            {sigma02?.toFixed(2)} MPa
          </Descriptions.Item>
          <Descriptions.Item label="Ultimate Strength">
            {sigmaMax?.toFixed(2)} MPa
          </Descriptions.Item>
          <Descriptions.Item label="Fracture Strain">
            {fractureStrain !== null
              ? `${(fractureStrain * 100).toFixed(4)} %`
              : "미지정"}
          </Descriptions.Item>
        </Descriptions>
      </Card>

      {fractureStrain !== null && (
        <>
          <Divider />
          <Card title="Fatigue Parameters" size="small">
            <Paragraph>
              피로 해석에 사용되는 Basquin 법칙과 Coffin-Manson 법칙은 재료의
              고주기 및 저주기 피로 수명을 예측합니다.
            </Paragraph>
            <Paragraph strong>Basquin</Paragraph>
            <BlockMath
              math={String.raw`\sigma_a = \sigma'_f \cdot \left(2N_f\right)^b`}
            />
            <Paragraph>
              Basquin 식은 응력 진폭(<InlineMath math="\sigma_a"/>)과 피로 수명(<InlineMath math="N_f"/>)의
              관계를 나타냅니다.
            </Paragraph>
            <Paragraph strong>Coffin-Manson</Paragraph>
            <BlockMath
              math={String.raw`\varepsilon_a = \varepsilon'_f \cdot \left(2N_f\right)^c`}
            />
            <Paragraph>
              Coffin-Manson 식은 소성 변형률 진폭(<InlineMath math="\varepsilon_a"/>)과 수명의 관계를 설명하며
              저주기 피로 해석에 쓰입니다.
            </Paragraph>

            <Paragraph strong>Total Strain-Life (Manson–Coffin–Basquin)</Paragraph>
            <BlockMath
                math={String.raw`\varepsilon_a 
                = \frac{\sigma'_f}{E} \cdot \left(2N_f\right)^b 
                + \varepsilon'_f \cdot \left(2N_f\right)^c`}
            />
            <Paragraph>
                • 첫 항은 탄성 변형률, 두 번째 항은 소성 변형률로, 고주기/저주기 피로 수명을 모두 설명합니다.
            </Paragraph>
            <Row gutter={16}>
              <Col xs={24} md={12}>
                <Form.Item label="Basquin Coefficient σ′f (MPa)">
                  <InputNumber
                    min={1}
                    value={sigmaFPrime ?? undefined}
                    onChange={setSigmaFPrime}
                    style={{ width: "100%" }}
                  />
                </Form.Item>
              </Col>
              <Col xs={24} md={12}>
                <Form.Item label="Basquin Exponent b">
                  <InputNumber
                    step={0.01}
                    value={b ?? undefined}
                    onChange={setB}
                    style={{ width: "100%" }}
                  />
                </Form.Item>
              </Col>
              <Col xs={24} md={12}>
                <Form.Item label="Coffin-Manson Coefficient ε′f">
                  <InputNumber
                    min={0}
                    step={0.0001}
                    value={epsilonFPrime ?? undefined}
                    onChange={setEpsilonFPrime}
                    style={{ width: "100%" }}
                  />
                </Form.Item>
              </Col>
              <Col xs={24} md={12}>
                <Form.Item label="Coffin-Manson Exponent c">
                  <InputNumber
                    step={0.01}
                    value={c ?? undefined}
                    onChange={setC}
                    style={{ width: "100%" }}
                  />
                </Form.Item>
              </Col>
            </Row>
          </Card>
        </>
      )}

      {snData.length > 0 && (
        <>
          <Divider />
                     <Card
             title="SN Curve"
             size="small"
             style={{ marginBottom: "24px" }}
             styles={{ body: { padding: 0, height: "100%" } }}
             >
            <Plot
                data={snData}
                layout={{
                autosize: true,
                height: 400,
                margin: { l: 50, r: 30, t: 40, b: 50 },
                title: "SN Curve",
                xaxis: { title: "Cycles to failure (N)", type: "log" },
                yaxis: { title: "Stress Amplitude (MPa)", type: "log" },
                } as any}
                config={{ responsive: true }}
                useResizeHandler
                style={{ width: "100%", height: "100%" }}
            />
            </Card>

        </>
      )}

      {enData.length > 0 && (
        <>
          <Divider />
                     <Card
             title="ε-N Curve"
             size="small"
             style={{ marginBottom: "24px" }}
             styles={{ body: { padding: 0, height: "100%" } }}
             >
            <Plot
            data={enData}
            layout={{
                autosize: true,
                height: 400,
                margin: { l: 50, r: 30, t: 40, b: 50 },
                title: "ε-N Curve",
                xaxis: { title: "Cycles to failure (N)", type: "log" },
                yaxis: { title: "Strain Amplitude", type: "log" },
            } as any}
            config={{ responsive: true }}
            useResizeHandler
            style={{ width: "100%", height: "100%" }}
            />
            </Card>

        </>
      )}

        {fractureStrain !== null && (
        <>
            <Divider />
            <Card
            title="Total Strain-Life Curve"
            size="small"
            style={{ marginBottom: "24px" }}
            bodyStyle={{ padding: 0 }}
            >
            <Plot
                data={generateTotalStrainLifeCurve()}
                layout={{
                autosize: true,
                height: 400,
                margin: { l: 50, r: 30, t: 40, b: 50 },
                title: "Total Strain-Life Curve",
                xaxis: { title: "Cycles to failure (N)", type: "log" },
                yaxis: { title: "Strain Amplitude", type: "log" },
                } as any}
                config={{ responsive: true }}
                useResizeHandler
                style={{ width: "100%", height: "100%" }}
            />
            </Card>
        </>
        )}

    </>
  );
};

export default RambergOsgoodPanel;