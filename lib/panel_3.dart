import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:shimmer/shimmer.dart';
import 'package:dio/dio.dart';

class Panel3Page extends StatelessWidget {
  const Panel3Page({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: ComparativeStudyPage(),
    );
  }
}

class ComparativeStudyPage extends StatelessWidget {
  const ComparativeStudyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F4F9),
      appBar: AppBar(
        title: const Text("Panel 1", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.blue,
      ),
      body: const Padding(
        padding: EdgeInsets.all(20.0),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                "Panel 1: Geomagnetic Field Variations and Interplanetary Parameters",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 20),
              ReportCard(reportNumber: 1),
              SizedBox(width: 20),
              ReportCard(reportNumber: 2),
            ],
          ),
        ),
      ),
    );
  }
}

class ReportCard extends StatefulWidget {
  final int reportNumber;

  const ReportCard({super.key, required this.reportNumber});

  @override
  _ReportCardState createState() => _ReportCardState();
}

class _ReportCardState extends State<ReportCard> {
  final _dateController = TextEditingController();
  String? _selectedParameter;
  String? _errorMessage;
  List<FlSpot> _dataPoints = [];
  bool isLoading = false;
  final Dio _dio = Dio();

  final List<String> _parameters = [
    "ΔH(nT), Equatorial Electrojet(nT)",
    "IMF Magnitude Avg, nT",
    "Magnitude, Avg IMF Vr, nT",
    "Bx, GSE/GSM, nT",
    "By, GSE, nT",
    "By, GSM, nT",
    "Bz, GSM, nT",
    "Bz, GSE, nT",
    "Dst Index, nT",
  ];

  final Map<String, int> parameterMap = {
    "IMF Magnitude Avg, nT": 8,
    "Magnitude, Avg IMF Vr, nT": 9,
    "Bx, GSE/GSM, nT": 12,
    "By, GSE, nT": 13,
    "By, GSM, nT": 15,
    "Bz, GSM, nT": 16,
    "Bz, GSE, nT": 14,
    "Dst Index, nT": 40,
  };

  Future<void> loadGraphData() async {
    if (_dateController.text.isEmpty || _selectedParameter == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please select a date and parameter.")),
      );
      return;
    }

    setState(() {
      isLoading = true;
      _errorMessage = null;
      _dataPoints = [];
    });

    try {
      if (_selectedParameter == "ΔH(nT), Equatorial Electrojet(nT)") {
        await _loadMagneticFieldStrengthData();
        return;
      }

      List<String> parts = _dateController.text.split('-');
      int year = int.parse(parts[2]);
      int month = int.parse(parts[1]);
      int day = int.parse(parts[0]);

      String formattedDate =
          "$year${month.toString().padLeft(2, '0')}${day.toString().padLeft(2, '0')}";

      final selectedVar = parameterMap[_selectedParameter];
      if (selectedVar == null) {
        throw "Unsupported parameter selected.";
      }

      const url = 'https://omniweb.gsfc.nasa.gov/cgi/nx1.cgi';
      _dio.options.headers = {'Content-Type': 'application/x-www-form-urlencoded'};

      final data = {
        'activity': 'retrieve',
        'res': 'hour',
        'spacecraft': 'omni2',
        'start_date': formattedDate,
        'end_date': formattedDate,
        'vars': selectedVar,
      };

      final response = await _dio.post(url, data: FormData.fromMap(data));

      if (response.statusCode == 200) {
        List<List<FlSpot>> allSpots = _parseOmniData(response.data.toString());
        if (allSpots.isNotEmpty) {
          setState(() {
            _dataPoints = allSpots[0]; // Take first set of data since we're requesting one parameter
            _errorMessage = null;
          });
        } else {
          setState(() {
            _errorMessage = "No data available for selected parameters";
            _dataPoints = [];
          });
        }
      } else {
        setState(() {
          _errorMessage = 'Failed to retrieve data. Status: ${response.statusCode}';
          _dataPoints = [];
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = "Error loading data: $e";
        _dataPoints = [];
      });
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  List<List<FlSpot>> _parseOmniData(String responseData) {
    List<List<FlSpot>> allSpots = [];
    List<String> lines = responseData.split('\n');
    bool startReading = false;

    for (String line in lines) {
      if (line.contains("YEAR DOY HR")) {
        startReading = true;
        allSpots.add([]); // Initialize one list since we're requesting one parameter
        continue;
      }

      if (startReading && line.trim().isNotEmpty && line.contains(RegExp(r'^\d{4}'))) {
        List<String> parts = line.trim().split(RegExp(r'\s+'));
        if (parts.length >= 4) {
          int hour = int.parse(parts[2]); // Hour value
          double value = double.tryParse(parts[3]) ?? 0; // Data value
          // Skip invalid values (OMNIWeb often uses large numbers like 999.9 for missing data)
          if (value < 999) {
            allSpots[0].add(FlSpot(hour.toDouble(), value));
          }
        }
      }
    }

    // Sort spots by hour
    for (var spots in allSpots) {
      spots.sort((a, b) => a.x.compareTo(b.x));
    }

    return allSpots;
  }

  Future<void> _loadMagneticFieldStrengthData() async {
    try {
      final dateParts = _dateController.text.split('-');

      final day = int.parse(dateParts[0]);


      final month = int.parse(dateParts[1]);


      final year = int.parse(dateParts[2]);



      final formattedDateForDatabase = "${day.toString().padLeft(2, '0')}"
          "${month.toString().padLeft(2, '0')}"
          "${year.toString().substring(2)}";



      final database = FirebaseDatabase.instance.ref('ppm_data');


      final snapshot = await database.get();



      if (!snapshot.exists) {
        setState(() {
          _errorMessage = "No data found in the database.";
          _dataPoints = [];
        });
        return;
      }

      final Map<String, dynamic> data = Map<String, dynamic>.from(snapshot.value as Map);

      final List<Map<String, dynamic>> filteredData = data.values
          .map((entry) => Map<String, dynamic>.from(entry))
          .where((entry) => entry['date'] == formattedDateForDatabase)
          .toList();

      if (filteredData.isEmpty) {
        setState(() {
          _errorMessage = "No data available for the selected date: $formattedDateForDatabase";
          _dataPoints = [];
        });
        return;
      }

      final Map<int, List<double>> groupedByHour = {};
      for (final entry in filteredData) {
        final timeParts = entry['time'].split(':');
        final hour = int.parse(timeParts[0]);
        final magneticFieldStrength = double.parse(entry['magnetic_field_strength'].toString());
        if (!groupedByHour.containsKey(hour)) {
          groupedByHour[hour] = [];
        }
        groupedByHour[hour]!.add(magneticFieldStrength);
      }

      final List<FlSpot> points = [];
      groupedByHour.forEach((hour, values) {
        final avgStrength = values.reduce((a, b) => a + b) / values.length;
        points.add(FlSpot(hour.toDouble(), avgStrength));
      });

      points.sort((a, b) => a.x.compareTo(b.x));

      setState(() {
        _dataPoints = points;
        _errorMessage = null;
      });
    } catch (e) {
      setState(() {
        _dataPoints = [];
        _errorMessage = "Error loading data: $e";
      });
    }
  }

  int getDayNumber(int year, int month, int day) {
    final DateTime date = DateTime(year, month, day);
    final DateTime startOfYear = DateTime(year, 1, 1);
    return date.difference(startOfYear).inDays + 1;
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            TextField(
              controller: _dateController,
              decoration: const InputDecoration(
                labelText: "Select Date",
                suffixIcon: Icon(Icons.calendar_today),
              ),
              readOnly: true,
              onTap: () async {
                final DateTime? pickedDate = await showDatePicker(
                  context: context,
                  initialDate: DateTime.now(),
                  firstDate: DateTime(2000),
                  lastDate: DateTime.now(),
                );
                if (pickedDate != null) {
                  final formattedDateForDisplay =

                      "${pickedDate.day.toString().padLeft(2, '0')}-${pickedDate.month.toString().padLeft(2, '0')}-${pickedDate.year}";

                  _dateController.text = formattedDateForDisplay;
                }
              },
            ),
            const SizedBox(height: 20),
            DropdownButton<String>(
              isExpanded: true,
              value: _selectedParameter,
              hint: const Text("Select a parameter"),
              items: _parameters.map((String parameter) {
                return DropdownMenuItem<String>(
                  value: parameter,
                  child: Text(parameter),
                );
              }).toList(),
              onChanged: (value) {
                setState(() {
                  _selectedParameter = value;
                });
              },
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: loadGraphData,
              child: const Text("Load Graph Data", style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 20),
              Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.red),
              ),
            ],
            const SizedBox(height: 20),
            isLoading
                ? _buildShimmerEffect()
                : SizedBox(
              height: 300,
              child: LineChart(
                LineChartData(
                  lineBarsData: [
                    LineChartBarData(
                      spots: _dataPoints,
                      isCurved: true,
                      gradient: const LinearGradient(
                        colors: [Colors.blue, Colors.lightBlueAccent],
                      ),
                      barWidth: 4,
                      belowBarData: BarAreaData(show: false),
                    ),
                  ],
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      axisNameWidget: Text(
                        _selectedParameter ?? "Selected Parameter",
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                      ),
                      sideTitles: SideTitles(
                        showTitles: true,
                        interval: _selectedParameter == "ΔH(nT), Equatorial Electrojet(nT)" ? 1000 : 2,
                        reservedSize: 40,
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      axisNameWidget: const Text("Hour", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          return Text("${value.toInt()}h", style: const TextStyle(fontSize: 12));
                        },
                        interval: 4,
                        reservedSize: 30,
                      ),
                    ),
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                  ),
                  gridData: const FlGridData(show: true),
                  borderData: FlBorderData(show: true),
                  minX: 0,
                  maxX: 23,
                ),
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildShimmerEffect() {
    return Shimmer.fromColors(
      baseColor: Colors.grey[300]!,
      highlightColor: Colors.grey[100]!,
      child: Container(
        height: 300,
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }
}