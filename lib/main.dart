import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:fl_chart/fl_chart.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  runApp(const MultiGasSentinelApp());
}

class MultiGasSentinelApp extends StatelessWidget {
  const MultiGasSentinelApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Multi-Gas AI Sentinel',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF070B13),
        cardColor: const Color(0xFF0E1626),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF06B6D4),
          secondary: Color(0xFFA855F7),
          surface: Color(0xFF0E1626),
          error: Color(0xFFEF4444),
        ),
        textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
      ),
      home: const MainDashboardScreen(),
    );
  }
}

class MainDashboardScreen extends StatefulWidget {
  const MainDashboardScreen({super.key});

  @override
  State<MainDashboardScreen> createState() => _MainDashboardScreenState();
}

class _MainDashboardScreenState extends State<MainDashboardScreen> with SingleTickerProviderStateMixin {
  int _currentIndex = 0;
  String serverUrl = "http://10.0.2.2:8000/api/v1/status";
  bool isSimulatorMode = true;

  Timer? _telemetryTimer;
  String status = "SAFE";
  double confidence = 98.8;
  String parity = "OPTIMAL";
  String sewerPermit = "PERMITTED TO ENTER";

  double mq61 = 142.0, mq62 = 143.5, mq9 = 24.0, mq135 = 96.0, objTemp = 26.5, ambTemp = 24.2;
  String buttonState = "IDLE";
  bool exhaustFan = false;
  int fanRpm = 0;
  bool buzzerActive = false;
  String ledColor = "GREEN";
  String lcdLine1 = "Atmosphere Safe ";
  String lcdLine2 = "Monitoring...   ";

  bool isSecretAlertActive = false;

  final List<FlSpot> mq6History = [];
  final List<FlSpot> mq62History = [];
  final List<FlSpot> mq9History = [];
  final List<FlSpot> mq135History = [];
  final List<FlSpot> tempHistory = [];
  int timeStep = 0;

  final List<Map<String, dynamic>> incidentLogs = [];

  late AnimationController _fanAnimController;
  final Random _random = Random();

  @override
  void initState() {
    super.initState();
    _fanAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    // Initial dummy history
    for (int i = 0; i < 20; i++) {
      mq6History.add(FlSpot(i.toDouble(), 140.0 + _random.nextDouble() * 5));
      mq62History.add(FlSpot(i.toDouble(), 141.0 + _random.nextDouble() * 5));
      mq9History.add(FlSpot(i.toDouble(), 22.0 + _random.nextDouble() * 3));
      mq135History.add(FlSpot(i.toDouble(), 94.0 + _random.nextDouble() * 4));
      tempHistory.add(FlSpot(i.toDouble(), 26.0 + _random.nextDouble() * 1));
    }
    timeStep = 20;

    _addLog("INFO", "Multi-Gas AI Sentinel Edge Node Initialized.");
    _telemetryTimer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  @override
  void dispose() {
    _telemetryTimer?.cancel();
    _fanAnimController.dispose();
    super.dispose();
  }

  void _addLog(String severity, String message) {
    final timeStr = "${DateTime.now().hour.toString().padLeft(2, '0')}:${DateTime.now().minute.toString().padLeft(2, '0')}:${DateTime.now().second.toString().padLeft(2, '0')}";
    setState(() {
      incidentLogs.insert(0, {
        "time": timeStr,
        "severity": severity,
        "message": message,
      });
      if (incidentLogs.length > 100) incidentLogs.removeLast();
    });
  }

  Future<void> _tick() async {
    if (isSimulatorMode) {
      _generateSimulatedData();
    } else {
      await _fetchTelemetryFromBackend();
    }
    _evaluateSafetyState();
  }

  void _generateSimulatedData() {
    if (isSecretAlertActive) {
      // Keep fake alert active with slight natural noise
      mq61 += (_random.nextDouble() - 0.48) * 1.5;
      mq62 += (_random.nextDouble() - 0.48) * 1.2;
      mq9 += (_random.nextDouble() - 0.48) * 0.8;
      mq135 += (_random.nextDouble() - 0.48) * 0.9;
      objTemp += (_random.nextDouble() - 0.5) * 0.1;
      return;
    }

    double jitter(double val, double min, double max, double delta) {
      double step = (_random.nextDouble() - 0.5) * delta;
      return (val + step).clamp(min, max);
    }

    setState(() {
      mq61 = jitter(mq61, 135, 155, 1.8);
      mq62 = jitter(mq62, 136, 156, 1.6);
      mq9 = jitter(mq9, 18, 30, 0.9);
      mq135 = jitter(mq135, 88, 108, 1.4);
      objTemp = jitter(objTemp, 24.5, 29.5, 0.2);
      ambTemp = 24.0 + (_random.nextDouble() - 0.5) * 0.3;
    });
  }

  Future<void> _fetchTelemetryFromBackend() async {
    try {
      final response = await http.get(Uri.parse(serverUrl)).timeout(const Duration(seconds: 2));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          mq61 = (data['mq6_1'] as num?)?.toDouble() ?? mq61;
          mq62 = (data['mq6_2'] as num?)?.toDouble() ?? mq62;
          mq9 = (data['mq9'] as num?)?.toDouble() ?? mq9;
          mq135 = (data['mq135'] as num?)?.toDouble() ?? mq135;
          objTemp = (data['obj_temp'] as num?)?.toDouble() ?? objTemp;
          buttonState = data['system_button'] ?? buttonState;
        });
      }
    } catch (_) {
      // Soft fallback to simulator
      _generateSimulatedData();
    }
  }

  void _evaluateSafetyState() {
    setState(() {
      // Parity check
      final parityDelta = (mq61 - mq62).abs();
      if (parityDelta > 65) {
        parity = "PARITY MISMATCH";
      } else if (parityDelta > 25) {
        parity = "SENSOR DRIFT";
      } else {
        parity = "OPTIMAL";
      }

      // Safety Classification
      final isDanger = mq61 > 480 || mq9 > 350 || mq135 > 380 || objTemp > 48 || parity == "PARITY MISMATCH" || isSecretAlertActive;
      final isWarning = mq61 > 270 || mq9 > 45 || mq135 > 175 || objTemp > 38 || parity == "SENSOR DRIFT";

      if (isDanger) {
        status = "DANGER";
        sewerPermit = "LETHAL HAZARD - DO NOT ENTER";
        ledColor = "RED";
        buzzerActive = true;
        exhaustFan = true;
        fanRpm = 3200;
        lcdLine1 = "CRITICAL HAZARD!";
        lcdLine2 = "MQ6:${mq61.toStringAsFixed(0)} EVACUATE";
        confidence = 99.4;
        if (!_fanAnimController.isAnimating) {
          _fanAnimController.repeat();
        }
      } else if (isWarning) {
        status = "WARNING";
        sewerPermit = "WARNING - RESTRICTED ENTRY";
        ledColor = "AMBER";
        buzzerActive = true;
        exhaustFan = true;
        fanRpm = 1850;
        lcdLine1 = "ATMOS WARNING   ";
        lcdLine2 = "PPE MANDATORY   ";
        confidence = 97.5;
        if (!_fanAnimController.isAnimating) {
          _fanAnimController.repeat();
        }
      } else {
        status = "SAFE";
        sewerPermit = "PERMITTED TO ENTER";
        ledColor = "GREEN";
        buzzerActive = false;
        if (!exhaustFan) {
          fanRpm = 0;
          _fanAnimController.stop();
        }
        lcdLine1 = "Atmosphere Safe ";
        lcdLine2 = "Monitoring...   ";
        confidence = 98.8;
      }

      // Maintain rolling history
      if (mq6History.length >= 25) {
        mq6History.removeAt(0);
        mq62History.removeAt(0);
        mq9History.removeAt(0);
        mq135History.removeAt(0);
        tempHistory.removeAt(0);
      }
      mq6History.add(FlSpot(timeStep.toDouble(), mq61));
      mq62History.add(FlSpot(timeStep.toDouble(), mq62));
      mq9History.add(FlSpot(timeStep.toDouble(), mq9));
      mq135History.add(FlSpot(timeStep.toDouble(), mq135));
      tempHistory.add(FlSpot(timeStep.toDouble(), objTemp));
      timeStep++;
    });
  }

  // -------------------------------------------------------------
  // SECRET CHAOS TRIGGER LOGIC
  // -------------------------------------------------------------
  void triggerSecretMQ6Alert() {
    setState(() {
      isSecretAlertActive = true;
      mq61 = 785.4;
      mq62 = 210.2; // Massive 575.2 PPM parity mismatch
      exhaustFan = true;
      _evaluateSafetyState();
      _addLog("CRITICAL", "🚨 SECRET DRILL TRIGGERED: Injected fake MQ-6 Methane spike at 785.4 PPM on GPIO 32! Sensor parity mismatch 575.2 PPM!");
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFFEF4444),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        content: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.white),
            SizedBox(width: 10),
            Expanded(child: Text("🚨 SECRET ALERT: Fake MQ-6 Spike Injected (785.4 PPM)!", style: TextStyle(fontWeight: FontWeight.bold))),
          ],
        ),
        action: SnackBarAction(
          label: "DISARM",
          textColor: Colors.white,
          onPressed: disarmSecretAlert,
        ),
      ),
    );
  }

  void disarmSecretAlert() {
    setState(() {
      isSecretAlertActive = false;
      mq61 = 142.5;
      mq62 = 144.1;
      mq9 = 22.0;
      mq135 = 95.0;
      objTemp = 26.4;
      exhaustFan = false;
      _evaluateSafetyState();
      _addLog("INFO", "🟢 DRILL DISARMED: System atmospheric baseline restored to nominal safe parameters.");
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF10B981),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        content: const Row(
          children: [
            Icon(Icons.check_circle_outline, color: Colors.white),
            SizedBox(width: 10),
            Text("🟢 System Disarmed & Clean Air Restored", style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  void openChaosModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          return Container(
            height: MediaQuery.of(context).size.height * 0.85,
            decoration: const BoxDecoration(
              color: Color(0xFF0D1424),
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              border: Border(top: BorderSide(color: Color(0xFFEF4444), width: 2)),
            ),
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.security, color: Color(0xFFEF4444), size: 24),
                        const SizedBox(width: 8),
                        Text("SECRET CHAOS & DRILL COCKPIT", style: GoogleFonts.orbitron(fontSize: 14, fontWeight: FontWeight.bold, color: const Color(0xFFFCA5A5))),
                      ],
                    ),
                    IconButton(icon: const Icon(Icons.close, color: Colors.white70), onPressed: () => Navigator.pop(ctx)),
                  ],
                ),
                const SizedBox(height: 16),

                // Big Hero Fake MQ-6 Spike Button
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFEF4444),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 8,
                      shadowColor: const Color(0xFFEF4444).withOpacity(0.6),
                    ),
                    icon: const Icon(Icons.emergency, color: Colors.white),
                    label: Text("🚨 EXECUTE SECRET MQ-6 SPIKE (ALERT)", style: GoogleFonts.orbitron(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
                    onPressed: () {
                      triggerSecretMQ6Alert();
                      Navigator.pop(ctx);
                    },
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFF10B981), width: 1.5),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    icon: const Icon(Icons.check_circle_outline, color: Color(0xFF10B981)),
                    label: Text("🟢 DISARM DRILL & RESTORE CLEAN AIR", style: GoogleFonts.orbitron(fontSize: 11, fontWeight: FontWeight.bold, color: const Color(0xFF10B981))),
                    onPressed: () {
                      disarmSecretAlert();
                      Navigator.pop(ctx);
                    },
                  ),
                ),
                const SizedBox(height: 20),

                Text("QUICK DRILL PRESETS", style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: const Color(0xFF94A3B8))),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _presetChip("Clean Air", () { disarmSecretAlert(); Navigator.pop(ctx); }),
                    _presetChip("Methane Spike (MQ6)", () { triggerSecretMQ6Alert(); Navigator.pop(ctx); }),
                    _presetChip("Parity Desync", () {
                      setState(() { isSecretAlertActive = true; mq61 = 480.0; mq62 = 120.0; _evaluateSafetyState(); });
                      Navigator.pop(ctx);
                    }),
                    _presetChip("Toxic Ammonia (MQ135)", () {
                      setState(() { isSecretAlertActive = true; mq135 = 560.0; exhaustFan = true; _evaluateSafetyState(); });
                      Navigator.pop(ctx);
                    }),
                    _presetChip("Cable Fire (MQ9 + Temp)", () {
                      setState(() { isSecretAlertActive = true; mq9 = 380.0; objTemp = 68.5; exhaustFan = true; _evaluateSafetyState(); });
                      Navigator.pop(ctx);
                    }),
                  ],
                ),
                const SizedBox(height: 20),

                Text("MANUAL SENSOR ADJUSTMENT", style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: const Color(0xFF94A3B8))),
                Expanded(
                  child: ListView(
                    children: [
                      _sliderTile("MQ-6 Primary (GPIO 32)", mq61, 0, 1000, "ppm", (v) {
                        setModalState(() => mq61 = v);
                        setState(() { isSecretAlertActive = true; mq61 = v; _evaluateSafetyState(); });
                      }),
                      _sliderTile("MQ-6 Redundant (GPIO 33)", mq62, 0, 1000, "ppm", (v) {
                        setModalState(() => mq62 = v);
                        setState(() { isSecretAlertActive = true; mq62 = v; _evaluateSafetyState(); });
                      }),
                      _sliderTile("MQ-9 Carbon Monoxide (GPIO 34)", mq9, 0, 600, "ppm", (v) {
                        setModalState(() => mq9 = v);
                        setState(() { isSecretAlertActive = true; mq9 = v; _evaluateSafetyState(); });
                      }),
                      _sliderTile("MQ-135 Toxics (GPIO 35)", mq135, 0, 800, "ppm", (v) {
                        setModalState(() => mq135 = v);
                        setState(() { isSecretAlertActive = true; mq135 = v; _evaluateSafetyState(); });
                      }),
                      _sliderTile("MLX90614 IR Temp (GPIO 12/26)", objTemp, 0, 100, "°C", (v) {
                        setModalState(() => objTemp = v);
                        setState(() { isSecretAlertActive = true; objTemp = v; _evaluateSafetyState(); });
                      }),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _presetChip(String label, VoidCallback onTap) {
    return ActionChip(
      backgroundColor: const Color(0xFF1E293B),
      side: const BorderSide(color: Color(0xFF334155)),
      label: Text(label, style: const TextStyle(fontSize: 11, color: Colors.white)),
      onPressed: onTap,
    );
  }

  Widget _sliderTile(String title, double val, double min, double max, String unit, ValueChanged<double> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(title, style: const TextStyle(fontSize: 11, color: Color(0xFFCBD5E1))),
            Text("${val.toStringAsFixed(1)} $unit", style: GoogleFonts.orbitron(fontSize: 11, color: const Color(0xFF06B6D4), fontWeight: FontWeight.bold)),
          ],
        ),
        Slider(
          value: val.clamp(min, max),
          min: min,
          max: max,
          activeColor: const Color(0xFF06B6D4),
          inactiveColor: const Color(0xFF1E293B),
          onChanged: onChanged,
        ),
      ],
    );
  }

  Color _getStatusColor() {
    if (status == "DANGER") return const Color(0xFFEF4444);
    if (status == "WARNING") return const Color(0xFFF59E0B);
    return const Color(0xFF10B981);
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = _getStatusColor();

    final List<Widget> pages = [
      // TAB 1: SAFETY GAUGES & HARDWARE
      SafetyGaugesTab(
        status: status,
        confidence: confidence,
        parity: parity,
        sewerPermit: sewerPermit,
        statusColor: statusColor,
        mq61: mq61,
        mq62: mq62,
        mq9: mq9,
        mq135: mq135,
        objTemp: objTemp,
        ambTemp: ambTemp,
        lcdLine1: lcdLine1,
        lcdLine2: lcdLine2,
        buzzerActive: buzzerActive,
        ledColor: ledColor,
        fanRpm: fanRpm,
        exhaustFan: exhaustFan,
        fanAnimation: _fanAnimController,
        onToggleFan: () {
          setState(() {
            exhaustFan = !exhaustFan;
            if (exhaustFan) {
              fanRpm = 1850;
              _fanAnimController.repeat();
            } else {
              fanRpm = 0;
              _fanAnimController.stop();
            }
          });
        },
        onResetCalib: disarmSecretAlert,
        onAlarmTest: () {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Buzzer Diagnostic Test Pulse Executed")));
        },
      ),

      // TAB 2: LIVE OSCILLOSCOPE
      LiveOscilloscopeTab(
        mq6History: mq6History,
        mq62History: mq62History,
        mq9History: mq9History,
        mq135History: mq135History,
        tempHistory: tempHistory,
        mq61: mq61,
        mq62: mq62,
        mq9: mq9,
        mq135: mq135,
        objTemp: objTemp,
      ),

      // TAB 3: GAS PROPORTIONS
      GasProportionsTab(
        mq61: mq61,
        mq9: mq9,
        mq135: mq135,
      ),

      // TAB 4: SEWER PERMIT & LOGS
      SewerPermitLogsTab(
        status: status,
        sewerPermit: sewerPermit,
        statusColor: statusColor,
        mq61: mq61,
        mq9: mq9,
        mq135: mq135,
        objTemp: objTemp,
        parity: parity,
        parityDelta: (mq61 - mq62).abs(),
        incidentLogs: incidentLogs,
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0F1D),
        elevation: 0,
        title: Row(
          children: [
            GestureDetector(
              onTap: openChaosModal,
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFF06B6D4), Color(0xFF3B82F6)]),
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(color: const Color(0xFF06B6D4).withOpacity(0.4), blurRadius: 10),
                  ],
                ),
                child: const Icon(Icons.shield_outlined, color: Colors.white, size: 20),
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("AI SENTINEL", style: GoogleFonts.orbitron(fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 1.5, color: Colors.white)),
                Text("ESP32 EDGE NODE // LIVE", style: GoogleFonts.shareTechMono(fontSize: 9, color: const Color(0xFF06B6D4))),
              ],
            ),
          ],
        ),
        actions: [
          // Stealth Secret Header Button
          GestureDetector(
            onTap: openChaosModal,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444).withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFEF4444).withOpacity(0.6), style: BorderStyle.solid),
              ),
              child: const Row(
                children: [
                  Icon(Icons.bolt, color: Color(0xFFFCA5A5), size: 14),
                  SizedBox(width: 4),
                  Text("SEC-OPS", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFFFCA5A5))),
                ],
              ),
            ),
          ),
          // Parity Badge
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: statusColor),
            ),
            child: Center(
              child: Text(parity, style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
      body: pages[_currentIndex],
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFFEF4444),
        elevation: 10,
        shape: const CircleBorder(),
        tooltip: "Secret Chaos Trigger",
        onPressed: openChaosModal,
        child: const Icon(Icons.crisis_alert, color: Colors.white, size: 26),
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Color(0xFF1E293B), width: 1)),
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (i) => setState(() => _currentIndex = i),
          backgroundColor: const Color(0xFF0A0F1D),
          selectedItemColor: const Color(0xFF06B6D4),
          unselectedItemColor: const Color(0xFF64748B),
          selectedLabelStyle: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold),
          unselectedLabelStyle: GoogleFonts.inter(fontSize: 10),
          type: BottomNavigationBarType.fixed,
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.dashboard_customize_outlined), activeIcon: Icon(Icons.dashboard_customize), label: "Gauges"),
            BottomNavigationBarItem(icon: Icon(Icons.show_chart_rounded), label: "Waveform"),
            BottomNavigationBarItem(icon: Icon(Icons.pie_chart_outline_rounded), activeIcon: Icon(Icons.pie_chart_rounded), label: "Gas Share"),
            BottomNavigationBarItem(icon: Icon(Icons.assignment_turned_in_outlined), activeIcon: Icon(Icons.assignment_turned_in), label: "Permit"),
          ],
        ),
      ),
    );
  }
}

// -------------------------------------------------------------
// TAB 1: SAFETY GAUGES & VIRTUAL HARDWARE
// -------------------------------------------------------------
class SafetyGaugesTab extends StatelessWidget {
  final String status;
  final double confidence;
  final String parity;
  final String sewerPermit;
  final Color statusColor;
  final double mq61, mq62, mq9, mq135, objTemp, ambTemp;
  final String lcdLine1, lcdLine2;
  final bool buzzerActive;
  final String ledColor;
  final int fanRpm;
  final bool exhaustFan;
  final AnimationController fanAnimation;
  final VoidCallback onToggleFan;
  final VoidCallback onResetCalib;
  final VoidCallback onAlarmTest;

  const SafetyGaugesTab({
    super.key,
    required this.status,
    required this.confidence,
    required this.parity,
    required this.sewerPermit,
    required this.statusColor,
    required this.mq61,
    required this.mq62,
    required this.mq9,
    required this.mq135,
    required this.objTemp,
    required this.ambTemp,
    required this.lcdLine1,
    required this.lcdLine2,
    required this.buzzerActive,
    required this.ledColor,
    required this.fanRpm,
    required this.exhaustFan,
    required this.fanAnimation,
    required this.onToggleFan,
    required this.onResetCalib,
    required this.onAlarmTest,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Decision Hero Banner
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: LinearGradient(
                colors: [statusColor.withOpacity(0.25), const Color(0xFF0E1626)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border.all(color: statusColor.withOpacity(0.6), width: 1.5),
              boxShadow: [
                BoxShadow(color: statusColor.withOpacity(0.15), blurRadius: 20, spreadRadius: 2),
              ],
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("OVERALL SEWER SAFETY PERMIT", style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: const Color(0xFF94A3B8), letterSpacing: 1)),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: statusColor.withOpacity(0.2), borderRadius: BorderRadius.circular(6)),
                      child: Text(status, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: statusColor)),
                    )
                  ],
                ),
                const SizedBox(height: 8),
                Text(sewerPermit, textAlign: TextAlign.center, style: GoogleFonts.orbitron(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                const SizedBox(height: 6),
                Text("AI Confidence: ${confidence.toStringAsFixed(1)}% • Parity: $parity", style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 11)),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // Sensor Cards Grid
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("REAL-TIME SENSOR GAUGES", style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: const Color(0xFF64748B), letterSpacing: 1)),
              Text("5 CHANNELS ACTIVE", style: GoogleFonts.shareTechMono(fontSize: 10, color: const Color(0xFF06B6D4))),
            ],
          ),
          const SizedBox(height: 10),

          _buildSensorCard("MQ-6 Primary Combustible", mq61, 0, 1000, "ppm", 270, 480, "Methane (CH4), LPG • GPIO 32", const Color(0xFF06B6D4)),
          const SizedBox(height: 8),
          _buildSensorCard("MQ-6 Redundant Parity", mq62, 0, 1000, "ppm", 270, 480, "Sensor Parity Check • GPIO 33", const Color(0xFFA855F7)),
          const SizedBox(height: 8),
          _buildSensorCard("MQ-9 Carbon Monoxide", mq9, 0, 600, "ppm", 45, 350, "CO, Smoldering Fire • GPIO 34", const Color(0xFFF59E0B)),
          const SizedBox(height: 8),
          _buildSensorCard("MQ-135 Toxic Sewer Gas", mq135, 0, 800, "ppm", 175, 380, "Ammonia, Benzene • GPIO 35", const Color(0xFFF43F5E)),
          const SizedBox(height: 8),
          _buildSensorCard("MLX90614 Thermal IR", objTemp, 0, 100, "°C", 38, 48, "Surface Heat • I2C (GPIO 12/26)", const Color(0xFF10B981)),

          const SizedBox(height: 20),

          // VIRTUAL HARDWARE ACTUATORS SECTION
          Text("EDGE HARDWARE ACTUATOR STATION", style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: const Color(0xFF64748B), letterSpacing: 1)),
          const SizedBox(height: 10),

          // 1. Virtual 16x2 LCD Bezel
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF0B1410),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF1A3326), width: 2),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.tv, color: Color(0xFF10B981), size: 14),
                        const SizedBox(width: 6),
                        Text("16x2 HD44780 LCD DISPLAY", style: GoogleFonts.orbitron(fontSize: 10, fontWeight: FontWeight.bold, color: const Color(0xFF10B981))),
                      ],
                    ),
                    const Text("GPIO 27,14,13,4,22,21", style: TextStyle(fontSize: 9, color: Color(0xFF64748B))),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF05100B),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFF0F3D28)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(lcdLine1, style: GoogleFonts.shareTechMono(fontSize: 15, color: const Color(0xFF00FF88), letterSpacing: 2)),
                      Text(lcdLine2, style: GoogleFonts.shareTechMono(fontSize: 15, color: const Color(0xFF00FF88), letterSpacing: 2)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // 2. Hardware Actuators Row (Buzzer, LED, Fan)
          Row(
            children: [
              // Active Buzzer
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0E1626),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: buzzerActive ? const Color(0xFFEF4444) : const Color(0xFF1E293B)),
                  ),
                  child: Column(
                    children: [
                      Icon(Icons.volume_up, color: buzzerActive ? const Color(0xFFEF4444) : const Color(0xFF64748B), size: 24),
                      const SizedBox(height: 4),
                      Text("BUZZER", style: GoogleFonts.orbitron(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white)),
                      Text(buzzerActive ? "SIREN ON" : "IDLE", style: TextStyle(fontSize: 9, color: buzzerActive ? const Color(0xFFEF4444) : const Color(0xFF64748B), fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // Status LED
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0E1626),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFF1E293B)),
                  ),
                  child: Column(
                    children: [
                      Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: ledColor == "RED" ? const Color(0xFFEF4444) : (ledColor == "AMBER" ? const Color(0xFFF59E0B) : const Color(0xFF10B981)),
                          boxShadow: [
                            BoxShadow(
                              color: (ledColor == "RED" ? const Color(0xFFEF4444) : (ledColor == "AMBER" ? const Color(0xFFF59E0B) : const Color(0xFF10B981))).withOpacity(0.6),
                              blurRadius: 10,
                            )
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text("LED GPIO 18", style: GoogleFonts.orbitron(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white)),
                      Text("$ledColor STATE", style: const TextStyle(fontSize: 9, color: Color(0xFF94A3B8))),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // Ventilation Fan
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0E1626),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: exhaustFan ? const Color(0xFF06B6D4) : const Color(0xFF1E293B)),
                  ),
                  child: Column(
                    children: [
                      RotationTransition(
                        turns: fanAnimation,
                        child: Icon(Icons.toys, color: exhaustFan ? const Color(0xFF06B6D4) : const Color(0xFF64748B), size: 24),
                      ),
                      const SizedBox(height: 4),
                      Text("FAN RELAY", style: GoogleFonts.orbitron(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white)),
                      Text("$fanRpm RPM", style: TextStyle(fontSize: 9, color: exhaustFan ? const Color(0xFF06B6D4) : const Color(0xFF64748B), fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Hardware Buttons Row
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFF1E293B)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.refresh, size: 14, color: Colors.white70),
                  label: const Text("Zero Calibration", style: TextStyle(fontSize: 11, color: Colors.white)),
                  onPressed: onResetCalib,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFF1E293B)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.air, size: 14, color: Color(0xFF0680B6D)),
                  label: Text(exhaustFan ? "Stop Fan" : "Force Fan", style: const TextStyle(fontSize: 11, color: Color(0xFF06B6D4))),
                  onPressed: onToggleFan,
                ),
              ),
            ],
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildSensorCard(String title, double val, double min, double max, String unit, double warnThresh, double dangerThresh, String sub, Color accent) {
    final pct = ((val - min) / (max - min)).clamp(0.0, 1.0);
    final isDanger = val >= dangerThresh;
    final isWarn = val >= warnThresh;
    final tag = isDanger ? "DANGER" : (isWarn ? "WARN" : "SAFE");
    final tagColor = isDanger ? const Color(0xFFEF4444) : (isWarn ? const Color(0xFFF59E0B) : const Color(0xFF10B981));

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0E1626),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isDanger ? const Color(0xFFEF4444).withOpacity(0.6) : const Color(0xFF1E293B)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: tagColor.withOpacity(0.15), borderRadius: BorderRadius.circular(6)),
                child: Text(tag, style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: tagColor)),
              )
            ],
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text("${val.toStringAsFixed(1)} $unit", style: GoogleFonts.orbitron(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
              Text(sub, style: const TextStyle(fontSize: 9, color: Color(0xFF64748B))),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 5,
              backgroundColor: const Color(0xFF1E293B),
              valueColor: AlwaysStoppedAnimation<Color>(tagColor),
            ),
          ),
        ],
      ),
    );
  }
}

// -------------------------------------------------------------
// TAB 2: LIVE MULTI-SENSOR OSCILLOSCOPE
// -------------------------------------------------------------
class LiveOscilloscopeTab extends StatelessWidget {
  final List<FlSpot> mq6History, mq62History, mq9History, mq135History, tempHistory;
  final double mq61, mq62, mq9, mq135, objTemp;

  const LiveOscilloscopeTab({
    super.key,
    required this.mq6History,
    required this.mq62History,
    required this.mq9History,
    required this.mq135History,
    required this.tempHistory,
    required this.mq61,
    required this.mq62,
    required this.mq9,
    required this.mq135,
    required this.objTemp,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("LIVE TIME-SERIES OSCILLOSCOPE", style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: const Color(0xFF64748B))),
              Text("ROLLING 25 SECONDS", style: GoogleFonts.shareTechMono(fontSize: 10, color: const Color(0xFF06B6D4))),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            height: 300,
            padding: const EdgeInsets.fromLTRB(10, 20, 20, 10),
            decoration: BoxDecoration(
              color: const Color(0xFF0E1626),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFF1E293B)),
            ),
            child: LineChart(
              LineChartData(
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (value) => const FlLine(color: Color(0xFF1E293B), strokeWidth: 1),
                ),
                titlesData: const FlTitlesData(
                  rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  LineChartBarData(spots: mq6History, isCurved: true, color: const Color(0xFF06B6D4), barWidth: 2.5, dotData: const FlDotData(show: false)),
                  LineChartBarData(spots: mq62History, isCurved: true, color: const Color(0xFFA855F7), barWidth: 2.0, isStrokeCapRound: true, dotData: const FlDotData(show: false)),
                  LineChartBarData(spots: mq9History, isCurved: true, color: const Color(0xFFF59E0B), barWidth: 2.2, dotData: const FlDotData(show: false)),
                  LineChartBarData(spots: mq135History, isCurved: true, color: const Color(0xFFF43F5E), barWidth: 2.2, dotData: const FlDotData(show: false)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _buildLegendTile("MQ-6 Primary (CH4 / LPG)", mq61, "ppm", const Color(0xFF06B6D4)),
          const SizedBox(height: 8),
          _buildLegendTile("MQ-6 Redundant (Parity)", mq62, "ppm", const Color(0xFFA855F7)),
          const SizedBox(height: 8),
          _buildLegendTile("MQ-9 Carbon Monoxide (CO)", mq9, "ppm", const Color(0xFFF59E0B)),
          const SizedBox(height: 8),
          _buildLegendTile("MQ-135 Toxic Sewer Air", mq135, "ppm", const Color(0xFFF43F5E)),
          const SizedBox(height: 8),
          _buildLegendTile("MLX90614 IR Surface Temp", objTemp, "°C", const Color(0xFF10B981)),
        ],
      ),
    );
  }

  Widget _buildLegendTile(String label, double val, String unit, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF0E1626),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF1E293B)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              CircleAvatar(radius: 5, backgroundColor: color),
              const SizedBox(width: 10),
              Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Colors.white)),
            ],
          ),
          Text("${val.toStringAsFixed(1)} $unit", style: GoogleFonts.orbitron(color: color, fontWeight: FontWeight.bold, fontSize: 13)),
        ],
      ),
    );
  }
}

// -------------------------------------------------------------
// TAB 3: GAS CONCENTRATION & EXPLOSION METRICS
// -------------------------------------------------------------
class GasProportionsTab extends StatelessWidget {
  final double mq61, mq9, mq135;

  const GasProportionsTab({
    super.key,
    required this.mq61,
    required this.mq9,
    required this.mq135,
  });

  @override
  Widget build(BuildContext context) {
    final double totalGas = (mq61 + mq9 + mq135) > 0 ? (mq61 + mq9 + mq135) : 1.0;
    final double pMq6 = (mq61 / totalGas) * 100;
    final double pMq9 = (mq9 / totalGas) * 100;
    final double pMq135 = (mq135 / totalGas) * 100;
    final double lelPct = ((mq61 / 1000) * 20).clamp(0.0, 100.0);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("ATMOSPHERIC SHARE BREAKDOWN", style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: const Color(0xFF64748B))),
          const SizedBox(height: 12),
          Container(
            height: 260,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF0E1626),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFF1E293B)),
            ),
            child: PieChart(
              PieChartData(
                sectionsSpace: 4,
                centerSpaceRadius: 55,
                sections: [
                  PieChartSectionData(color: const Color(0xFF06B6D4), value: pMq6, title: '${pMq6.toStringAsFixed(0)}%', radius: 50, titleStyle: GoogleFonts.orbitron(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white)),
                  PieChartSectionData(color: const Color(0xFFF59E0B), value: pMq9, title: '${pMq9.toStringAsFixed(0)}%', radius: 50, titleStyle: GoogleFonts.orbitron(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white)),
                  PieChartSectionData(color: const Color(0xFFF43F5E), value: pMq135, title: '${pMq135.toStringAsFixed(0)}%', radius: 50, titleStyle: GoogleFonts.orbitron(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // LEL Explosive Risk Gauge Card
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF0E1626),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF1E293B)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("LOWER EXPLOSIVE LIMIT (% LEL)", style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white)),
                    Text("${lelPct.toStringAsFixed(1)}% LEL", style: GoogleFonts.orbitron(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF06B6D4))),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: lelPct / 100,
                    minHeight: 6,
                    backgroundColor: const Color(0xFF1E293B),
                    valueColor: AlwaysStoppedAnimation<Color>(lelPct > 20 ? const Color(0xFFEF4444) : const Color(0xFF06B6D4)),
                  ),
                ),
                const SizedBox(height: 6),
                const Text("Safe confined space entry limit is < 10% LEL for combustible methane.", style: TextStyle(fontSize: 9, color: Color(0xFF64748B))),
              ],
            ),
          ),
          const SizedBox(height: 12),

          _buildRatioTile("Methane (MQ-6) Share", pMq6, "${mq61.toStringAsFixed(1)} ppm", const Color(0xFF06B6D4)),
          const SizedBox(height: 8),
          _buildRatioTile("Carbon Monoxide (MQ-9) Share", pMq9, "${mq9.toStringAsFixed(1)} ppm", const Color(0xFFF59E0B)),
          const SizedBox(height: 8),
          _buildRatioTile("Toxic Air / NH3 (MQ-135) Share", pMq135, "${mq135.toStringAsFixed(1)} ppm", const Color(0xFFF43F5E)),
        ],
      ),
    );
  }

  Widget _buildRatioTile(String label, double pct, String val, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0E1626),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF1E293B)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              CircleAvatar(radius: 5, backgroundColor: color),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Colors.white)),
                  Text(val, style: const TextStyle(fontSize: 9, color: Color(0xFF64748B))),
                ],
              ),
            ],
          ),
          Text("${pct.toStringAsFixed(1)}%", style: GoogleFonts.orbitron(color: color, fontWeight: FontWeight.bold, fontSize: 13)),
        ],
      ),
    );
  }
}

// -------------------------------------------------------------
// TAB 4: SEWER PERMIT & INCIDENT LOGS
// -------------------------------------------------------------
class SewerPermitLogsTab extends StatelessWidget {
  final String status, sewerPermit;
  final Color statusColor;
  final double mq61, mq9, mq135, objTemp;
  final String parity;
  final double parityDelta;
  final List<Map<String, dynamic>> incidentLogs;

  const SewerPermitLogsTab({
    super.key,
    required this.status,
    required this.sewerPermit,
    required this.statusColor,
    required this.mq61,
    required this.mq9,
    required this.mq135,
    required this.objTemp,
    required this.parity,
    required this.parityDelta,
    required this.incidentLogs,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Official Certificate Box
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF0E1626),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: statusColor.withOpacity(0.5), width: 1.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("DIGITAL CONFINED SPACE PERMIT", style: GoogleFonts.orbitron(fontSize: 11, fontWeight: FontWeight.bold, color: const Color(0xFF06B6D4))),
                    Text("#SEW-2026-0881", style: GoogleFonts.shareTechMono(fontSize: 10, color: const Color(0xFF64748B))),
                  ],
                ),
                const SizedBox(height: 10),
                Text(sewerPermit, style: GoogleFonts.orbitron(fontSize: 15, fontWeight: FontWeight.bold, color: statusColor)),
                const SizedBox(height: 12),
                const Divider(color: Color(0xFF1E293B)),
                const SizedBox(height: 8),

                _checklistRow("Methane < 270 ppm", mq61 < 270, "${mq61.toStringAsFixed(1)} ppm"),
                _checklistRow("Carbon Monoxide < 45 ppm", mq9 < 45, "${mq9.toStringAsFixed(1)} ppm"),
                _checklistRow("Toxic Gases < 175 ppm", mq135 < 175, "${mq135.toStringAsFixed(1)} ppm"),
                _checklistRow("Surface Temp < 38 °C", objTemp < 38, "${objTemp.toStringAsFixed(1)} °C"),
                _checklistRow("Dual MQ-6 Parity Synchronized", parity == "OPTIMAL", "Δ ${parityDelta.toStringAsFixed(1)} ppm"),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Incident Logs Timeline
          Text("REAL-TIME INCIDENT LOGS", style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: const Color(0xFF64748B))),
          const SizedBox(height: 10),

          if (incidentLogs.isEmpty)
            const Center(child: Text("No incident records available.", style: TextStyle(color: Color(0xFF64748B))))
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: incidentLogs.length,
              itemBuilder: (context, idx) {
                final log = incidentLogs[idx];
                final sev = log['severity'] as String;
                final color = sev == "CRITICAL" ? const Color(0xFFEF4444) : (sev == "WARNING" ? const Color(0xFFF59E0B) : const Color(0xFF06B6D4));

                return Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0E1626),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF1E293B)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(log['time'], style: GoogleFonts.shareTechMono(fontSize: 10, color: const Color(0xFF64748B))),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(color: color.withOpacity(0.2), borderRadius: BorderRadius.circular(4)),
                        child: Text(sev, style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: color)),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(log['message'], style: const TextStyle(fontSize: 10, color: Color(0xFFCBD5E1))),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _checklistRow(String label, bool pass, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(pass ? Icons.check_circle : Icons.cancel, color: pass ? const Color(0xFF10B981) : const Color(0xFFEF4444), size: 14),
              const SizedBox(width: 8),
              Text(label, style: const TextStyle(fontSize: 11, color: Colors.white70)),
            ],
          ),
          Text(value, style: GoogleFonts.shareTechMono(fontSize: 10, color: pass ? const Color(0xFF10B981) : const Color(0xFFEF4444))),
        ],
      ),
    );
  }
}
