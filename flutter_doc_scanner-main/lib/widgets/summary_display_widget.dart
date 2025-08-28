import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../services/offline_gemma_service.dart';

class SummaryDisplayWidget extends StatefulWidget {
  final PdfSummary summary;
  final String documentTitle;
  
  const SummaryDisplayWidget({
    Key? key,
    required this.summary,
    required this.documentTitle,
  }) : super(key: key);
  
  @override
  _SummaryDisplayWidgetState createState() => _SummaryDisplayWidgetState();
}

class _SummaryDisplayWidgetState extends State<SummaryDisplayWidget>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }
  
  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0D062C), Color(0xFF282467), Color(0xFF504AF2)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              _buildTabBar(),
              Expanded(
                child: Container(
                  margin: EdgeInsets.only(top: 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(25),
                      topRight: Radius.circular(25),
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(25),
                      topRight: Radius.circular(25),
                    ),
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        _buildSummaryTab(),
                        _buildKeyPointsTab(),
                        _buildStatsTab(),
                        _buildOriginalTab(),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildHeader() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
          SizedBox(width: 8),
          Icon(Icons.auto_awesome, color: Colors.white, size: 24),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'AI Summary',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  widget.documentTitle,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.8),
                    fontSize: 14,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.share, color: Colors.white),
            onPressed: _shareSummary,
          ),
        ],
      ),
    );
  }
  
  Widget _buildTabBar() {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: TabBar(
        controller: _tabController,
        indicator: BoxDecoration(
          color: Colors.white.withOpacity(0.2),
          borderRadius: BorderRadius.circular(12),
        ),
        labelColor: Colors.white,
        unselectedLabelColor: Colors.white.withOpacity(0.6),
        labelStyle: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
        tabs: [
          Tab(
            icon: Icon(Icons.description, size: 20),
            text: 'Summary',
          ),
          Tab(
            icon: Icon(Icons.list, size: 20),
            text: 'Key Points',
          ),
          Tab(
            icon: Icon(Icons.analytics, size: 20),
            text: 'Stats',
          ),
          Tab(
            icon: Icon(Icons.article, size: 20),
            text: 'Original',
          ),
        ],
      ),
    );
  }
  
  Widget _buildSummaryTab() {
    return SingleChildScrollView(
      padding: EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader('AI Generated Summary', Icons.auto_awesome),
          SizedBox(height: 16),
          
          // AI Model Badge
          Container(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Color(0xFF504AF2).withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Color(0xFF504AF2).withOpacity(0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.offline_bolt, color: Color(0xFF504AF2), size: 16),
                SizedBox(width: 6),
                Text(
                  widget.summary.modelUsed,
                  style: TextStyle(
                    color: Color(0xFF504AF2),
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          
          SizedBox(height: 16),
          
          // Summary Content
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey[200]!),
            ),
            child: Text(
              widget.summary.summary,
              style: TextStyle(
                fontSize: 14,
                height: 1.6,
                color: Colors.grey[800],
              ),
            ),
          ),
          
          SizedBox(height: 20),
          
          // Action Buttons
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _copySummary(widget.summary.summary),
                  icon: Icon(Icons.copy, size: 18),
                  label: Text('Copy Summary'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Color(0xFF504AF2),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _shareSummary,
                  icon: Icon(Icons.share, size: 18),
                  label: Text('Share'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Color(0xFF504AF2),
                    side: BorderSide(color: Color(0xFF504AF2)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
  
  Widget _buildKeyPointsTab() {
    return SingleChildScrollView(
      padding: EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader('Key Points', Icons.list),
          SizedBox(height: 20),
          
          ...widget.summary.keyPoints.asMap().entries.map((entry) {
            final index = entry.key;
            final point = entry.value;
            
            return Container(
              margin: EdgeInsets.only(bottom: 12),
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey[200]!),
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.1),
                    blurRadius: 4,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: Color(0xFF504AF2),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        '${index + 1}',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      point,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.5,
                        color: Colors.grey[800],
                      ),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
          
          SizedBox(height: 20),
          
          // Copy Key Points Button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _copyKeyPoints(),
              icon: Icon(Icons.copy, size: 18),
              label: Text('Copy Key Points'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Color(0xFF504AF2),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildStatsTab() {
    return SingleChildScrollView(
      padding: EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader('Processing Statistics', Icons.analytics),
          SizedBox(height: 20),
          
          // Stats Cards
          _buildStatCard(
            'Processing Time',
            '${widget.summary.processingTimeMs / 1000} seconds',
            Icons.timer,
            Colors.blue,
          ),
          SizedBox(height: 12),
          
          _buildStatCard(
            'Compression Ratio',
            '${(widget.summary.compressionRatio * 100).toInt()}%',
            Icons.compress,
            Colors.green,
          ),
          SizedBox(height: 12),
          
          _buildStatCard(
            'Original Words',
            '${widget.summary.originalText.split(' ').length.toString()}',
            Icons.article,
            Colors.orange,
          ),
          SizedBox(height: 12),
          
          _buildStatCard(
            'Summary Words',
            '${widget.summary.summary.split(' ').length.toString()}',
            Icons.short_text,
            Colors.purple,
          ),
          SizedBox(height: 12),
          
          _buildStatCard(
            'Processing Mode',
            widget.summary.isOffline ? 'Offline' : 'Online',
            widget.summary.isOffline ? Icons.offline_bolt : Icons.wifi,
            widget.summary.isOffline ? Colors.green : Colors.blue,
          ),
          SizedBox(height: 12),
          
          _buildStatCard(
            'AI Model',
            widget.summary.modelUsed,
            Icons.smart_toy,
            Color(0xFF504AF2),
          ),
          
          SizedBox(height: 24),
          
          // Performance Indicator
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _getPerformanceColor().withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _getPerformanceColor().withOpacity(0.3)),
            ),
            child: Column(
              children: [
                Icon(_getPerformanceIcon(), color: _getPerformanceColor(), size: 32),
                SizedBox(height: 8),
                Text(
                  _getPerformanceLabel(),
                  style: TextStyle(
                    color: _getPerformanceColor(),
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  _getPerformanceDescription(),
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 14,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildOriginalTab() {
    return SingleChildScrollView(
      padding: EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader('Original Text', Icons.article),
          SizedBox(height: 16),
          
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey[200]!),
            ),
            child: Text(
              widget.summary.originalText,
              style: TextStyle(
                fontSize: 14,
                height: 1.5,
                color: Colors.grey[700],
              ),
            ),
          ),
          
          SizedBox(height: 20),
          
          // Copy Original Button
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _copySummary(widget.summary.originalText),
              icon: Icon(Icons.copy, size: 18),
              label: Text('Copy Original Text'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Color(0xFF504AF2),
                side: BorderSide(color: Color(0xFF504AF2)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: Color(0xFF504AF2), size: 24),
        SizedBox(width: 12),
        Text(
          title,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.grey[800],
          ),
        ),
      ],
    );
  }
  
  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[800],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  Color _getPerformanceColor() {
    final seconds = widget.summary.processingTimeMs / 1000;
    if (seconds < 30) return Colors.green;
    if (seconds < 60) return Colors.orange;
    return Colors.red;
  }
  
  IconData _getPerformanceIcon() {
    final seconds = widget.summary.processingTimeMs / 1000;
    if (seconds < 30) return Icons.flash_on;
    if (seconds < 60) return Icons.schedule;
    return Icons.hourglass_full;
  }
  
  String _getPerformanceLabel() {
    final seconds = widget.summary.processingTimeMs / 1000;
    if (seconds < 30) return 'Excellent Performance';
    if (seconds < 60) return 'Good Performance';
    return 'Standard Performance';
  }
  
  String _getPerformanceDescription() {
    final seconds = widget.summary.processingTimeMs / 1000;
    if (seconds < 30) return 'Very fast processing - optimized for your device';
    if (seconds < 60) return 'Good processing speed for the document size';
    return 'Processing completed - large documents take more time';
  }
  
  void _copySummary(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Copied to clipboard'),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
  
  void _copyKeyPoints() {
    final keyPointsText = widget.summary.keyPoints
        .asMap()
        .entries
        .map((entry) => '${entry.key + 1}. ${entry.value}')
        .join('\n');
    
    _copySummary(keyPointsText);
  }
  
  void _shareSummary() {
    final shareText = '''
AI Summary of ${widget.documentTitle}

${widget.summary.summary}

Key Points:
${widget.summary.keyPoints.asMap().entries.map((entry) => '${entry.key + 1}. ${entry.value}').join('\n')}

Generated by ScanMate AI (${widget.summary.modelUsed})
Processing time: ${widget.summary.processingTimeMs / 1000} seconds
''';
    
    Share.share(shareText);
  }
}