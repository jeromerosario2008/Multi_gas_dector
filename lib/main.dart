import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:fl_chart/fl_chart.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  runApp(const MultiGasMonitorApp());
}

class MultiGasMonitorApp extends StatelessWidget {
  const MultiGasMonitorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Multi-Gas Monitor',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0A0E17),
        cardColor: const Color(0xFF121B2A),
        textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
      ),
      home: const MainNavigationScreen(),
    );
  }
}

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;

  // IMPORTANT: For Android Emulator use 10.0.2.2. For physical phone, use laptop's IPv4.
  static const String serverUrl = "http://10.0.2.2:8000/api/v1/status";

  Timer? _pollingTimer;
  String status = "CONNECTING...";
  int confidence = 98;
  String parity = "SYNCING";
  String sewerPermit = "EVALUATING";

  double mq61 = 0, mq62 = 0, mq9 = 0, mq135 = 0, objTemp = 25.0;
  String buttonState = "IDLE";

  final List<FlSpot> mq6History = [];
  final List<FlSpot> mq9History = [];
  final List<FlSpot> mq135History = [];
  int timeStep = 0;

  @override
  void initState() {
    super.initState();
    _pollingTimer = Timer.periodic(const Duration(seconds: 1), (timer) => fetchTelemetry());
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }

  Future<void> fetchTelemetry() async {
    try {
      final response = await http.get(Uri.parse(serverUrl)).timeout(const Duration(seconds: 2));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          status = data['status'] ?? "SAFE";
          confidence = data['confidence'] ?? 98;
          parity = data['parity'] ?? "OPTIMAL";
          mq61 = (data['mq6_1'] as num?)?.toDouble() ?? 0.0;
          mq62 = (data['mq6_2'] as num?)?.toDouble() ?? 0.0;
          mq9 = (data['mq9'] as num?)?.toDouble() ?? 0.0;
          mq135 = (data['mq135'] as num?)?.toDouble() ?? 0.0;
          objTemp = (data['obj_temp'] as num?)?.toDouble() ?? 25.0;
          buttonState = data['system_button'] ?? "IDLE";

          // Entry Safety Classification Logic
          if (status.contains("DANGER") || mq9 > 400 || mq135 > 450 || mq61 > 500) {
            sewerPermit = "LETHAL HAZARD - DO NOT ENTER";
          } else if (status.contains("WARN") || mq9 > 250 || mq135 > 280 || mq61 > 300) {
            sewerPermit = "WARNING - RESTRICTED ENTRY";
          } else {
            sewerPermit = "PERMITTED TO ENTER";
          }

          // Maintain rolling 20-point line chart window
          if (mq6History.length >= 20) {
            mq6History.removeAt(0);
            mq9History.removeAt(0);
            mq135History.removeAt(0);
          }
          mq6History.add(FlSpot(timeStep.toDouble(), mq61));
          mq9History.add(FlSpot(timeStep.toDouble(), mq9));
          mq135History.add(FlSpot(timeStep.toDouble(), mq135));
          timeStep++;
        });
      }
    } catch (_) {
      setState(() {
        status = "OFFLINE";
        sewerPermit = "SERVER UNREACHABLE";
      });
    }
  }

  Color getDangerColor() {
    if (status.contains("DANGER") || sewerPermit.contains("LETHAL")) return const Color(0xFFEF4444);
    if (status.contains("WARN") || sewerPermit.contains("RESTRICTED")) return const Color(0xFFF59E0B);
    return const Color(0xFF10B981);
  }

  @override
  Widget build(BuildContext context) {
    final dangerColor = getDangerColor();

    final List<Widget> pages = [
      OverviewPage(
        status: status,
        confidence: confidence,
        parity: parity,
        sewerPermit: sewerPermit,
        dangerColor: dangerColor,
        mq61: mq61,
        mq62: mq62,
        mq9: mq9,
        mq135: mq135,
        objTemp: objTemp,
        buttonState: buttonState,
      ),
      LiveWaveformPage(
        mq6History: mq6History,
        mq9History: mq9History,
        mq135History: mq135History,
        mq61: mq61,
        mq9: mq9,
        mq135: mq135,
      ),
      PieChartBreakdownPage(
        mq61: mq61,
        mq9: mq9,
        mq135: mq135,
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        elevation: 0,
        title: Text(
          "MULTI-GAS MONITOR",
          style: GoogleFonts.orbitron(letterSpacing: 2, fontWeight: FontWeight.bold, fontSize: 16),
        ),
        actions: [
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: dangerColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: dangerColor),
            ),
            child: Text(
              parity,
              style: TextStyle(color: dangerColor, fontSize: 11, fontWeight: FontWeight.bold),
            ),
          )
        ],
      ),
      body: pages[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        backgroundColor: const Color(0xFF0F172A),
        selectedItemColor: dangerColor,
        unselectedItemColor: const Color(0xFF64748B),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.shield_outlined), label: "Safety & Gauges"),
          BottomNavigationBarItem(icon: Icon(Icons.show_chart_rounded), label: "Live Waveform"),
          BottomNavigationBarItem(icon: Icon(Icons.pie_chart_outline_rounded), label: "Proportions"),
        ],
      ),
    );
  }
}

// -------------------------------------------------------------
// PAGE 1: SAFETY GAUGES & STATUS OVERVIEW
// -------------------------------------------------------------
class OverviewPage extends StatelessWidget {
  final String status;
  final int confidence;
  final String parity;
  final String sewerPermit;
  final Color dangerColor;
  final double mq61, mq62, mq9, mq135, objTemp;
  final String buttonState;

  const OverviewPage({
    super.key,
    required this.status,
    required this.confidence,
    required this.parity,
    required this.sewerPermit,
    required this.dangerColor,
    required this.mq61,
    required this.mq62,
    required this.mq9,
    required this.mq135,
    required this.objTemp,
    required this.buttonState,
  });

  String getLevelTag(double val, double warnThreshold, double dangerThreshold) {
    if (val >= dangerThreshold) return "DANGER";
    if (val >= warnThreshold) return "WARNING";
    return "SAFE";
  }

  Color getLevelColor(String tag) {
    if (tag == "DANGER") return const Color(0xFFEF4444);
    if (tag == "WARNING") return const Color(0xFFF59E0B);
    return const Color(0xFF10B981);
  }

  @override
  Widget build(BuildContext context) {
    final mq6Tag = getLevelTag(mq61, 300, 500);
    final mq9Tag = getLevelTag(mq9, 250, 400);
    final mq135Tag = getLevelTag(mq135, 280, 450);
    final tempTag = getLevelTag(objTemp, 45, 60);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Decision Banner
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: LinearGradient(
                colors: [dangerColor.withOpacity(0.3), const Color(0xFF121B2A)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border.all(color: dangerColor.withOpacity(0.6), width: 1.5),
            ),
            child: Column(
              children: [
                Text("OVERALL SAFETY INDEX", style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: const Color(0xFF94A3B8))),
                const SizedBox(height: 8),
                Text(sewerPermit, textAlign: TextAlign.center, style: GoogleFonts.orbitron(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                const SizedBox(height: 8),
                Text("AI Confidence: $confidence% • System: $status", style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text("SENSOR DANGER LEVELS", style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF64748B))),
          const SizedBox(height: 10),

          // 2x2 Sensor Cards Grid
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.25,
            children: [
              _buildSensorCard("MQ-6 METHANE", "${mq61.toStringAsFixed(1)} ADC", mq6Tag, getLevelColor(mq6Tag), "Redundant: ${mq62.toStringAsFixed(1)}"),
              _buildSensorCard("MQ-9 CARBON MONOXIDE", "${mq9.toStringAsFixed(1)} ADC", mq9Tag, getLevelColor(mq9Tag), "Combustible Gas"),
              _buildSensorCard("MQ-135 AIR QUALITY", "${mq135.toStringAsFixed(1)} ADC", mq135Tag, getLevelColor(mq135Tag), "NH3 / Benzene / Smoke"),
              _buildSensorCard("MLX90614 SURFACE IR", "${objTemp.toStringAsFixed(1)} °C", tempTag, getLevelColor(tempTag), "Non-Contact Heat"),
            ],
          ),

          const SizedBox(height: 16),
          // Button state banner
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF121B2A),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF1E293B)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("Hardware Interlock Button:", style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
                Text(buttonState, style: GoogleFonts.orbitron(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSensorCard(String title, String value, String tag, Color tagColor, String sub) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF121B2A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tagColor.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(child: Text(title, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF64748B)))),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: tagColor.withOpacity(0.2), borderRadius: BorderRadius.circular(6)),
                child: Text(tag, style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: tagColor)),
              )
            ],
          ),
          Text(value, style: GoogleFonts.orbitron(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
          Text(sub, style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8))),
        ],
      ),
    );
  }
}

// -------------------------------------------------------------
// PAGE 2: REAL-TIME MULTI-SENSOR WAVEFORM
// -------------------------------------------------------------
class LiveWaveformPage extends StatelessWidget {
  final List<FlSpot> mq6History;
  final List<FlSpot> mq9History;
  final List<FlSpot> mq135History;
  final double mq61, mq9, mq135;

  const LiveWaveformPage({
    super.key,
    required this.mq6History,
    required this.mq9History,
    required this.mq135History,
    required this.mq61,
    required this.mq9,
    required this.mq135,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("DYNAMIC TIME-SERIES CURVES", style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF64748B))),
          const SizedBox(height: 12),
          Container(
            height: 280,
            padding: const EdgeInsets.fromLTRB(10, 20, 20, 10),
            decoration: BoxDecoration(
              color: const Color(0xFF121B2A),
              borderRadius: BorderRadius.circular(20),
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
                  LineChartBarData(spots: mq6History, isCurved: true, color: const Color(0xFF38BDF8), barWidth: 2.5, dotData: const FlDotData(show: false)),
                  LineChartBarData(spots: mq9History, isCurved: true, color: const Color(0xFFFBBF24), barWidth: 2.5, dotData: const FlDotData(show: false)),
                  LineChartBarData(spots: mq135History, isCurved: true, color: const Color(0xFFF43F5E), barWidth: 2.5, dotData: const FlDotData(show: false)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _buildLegendTile("MQ-6 Methane (CH4)", "${mq61.toStringAsFixed(1)} ADC", const Color(0xFF38BDF8)),
          const SizedBox(height: 8),
          _buildLegendTile("MQ-9 Carbon Monoxide (CO)", "${mq9.toStringAsFixed(1)} ADC", const Color(0xFFFBBF24)),
          const SizedBox(height: 8),
          _buildLegendTile("MQ-135 Air Quality / NH3", "${mq135.toStringAsFixed(1)} ADC", const Color(0xFFF43F5E)),
        ],
      ),
    );
  }

  Widget _buildLegendTile(String label, String val, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF121B2A),
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
              Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.white)),
            ],
          ),
          Text(val, style: GoogleFonts.orbitron(color: color, fontWeight: FontWeight.bold, fontSize: 14)),
        ],
      ),
    );
  }
}

// -------------------------------------------------------------
// PAGE 3: PIE CHART CONCENTRATION RATIO
// -------------------------------------------------------------
class PieChartBreakdownPage extends StatelessWidget {
  final double mq61, mq9, mq135;

  const PieChartBreakdownPage({
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

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("GAS CONCENTRATION BREAKDOWN", style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF64748B))),
          const SizedBox(height: 12),
          Container(
            height: 280,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF121B2A),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFF1E293B)),
            ),
            child: PieChart(
              PieChartData(
                sectionsSpace: 4,
                centerSpaceRadius: 50,
                sections: [
                  PieChartSectionData(color: const Color(0xFF38BDF8), value: pMq6, title: '${pMq6.toStringAsFixed(0)}%', radius: 55, titleStyle: GoogleFonts.orbitron(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
                  PieChartSectionData(color: const Color(0xFFFBBF24), value: pMq9, title: '${pMq9.toStringAsFixed(0)}%', radius: 55, titleStyle: GoogleFonts.orbitron(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
                  PieChartSectionData(color: const Color(0xFFF43F5E), value: pMq135, title: '${pMq135.toStringAsFixed(0)}%', radius: 55, titleStyle: GoogleFonts.orbitron(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _buildRatioTile("Methane (MQ-6) Share", pMq6, const Color(0xFF38BDF8)),
          const SizedBox(height: 8),
          _buildRatioTile("Carbon Monoxide (MQ-9) Share", pMq9, const Color(0xFFFBBF24)),
          const SizedBox(height: 8),
          _buildRatioTile("Toxic / Air Quality (MQ-135) Share", pMq135, const Color(0xFFF43F5E)),
        ],
      ),
    );
  }

  Widget _buildRatioTile(String label, double pct, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF121B2A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF1E293B)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              CircleAvatar(radius: 5, backgroundColor: color),
              const SizedBox(width: 10),
              Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.white)),
            ],
          ),
          Text("${pct.toStringAsFixed(1)}%", style: GoogleFonts.orbitron(color: color, fontWeight: FontWeight.bold, fontSize: 14)),
        ],
      ),
    );
  }
}
