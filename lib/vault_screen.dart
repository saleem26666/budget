import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // ✅ ADDED FOR HapticFeedback
import 'dart:convert';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'app_theme.dart';
import 'database_helper.dart';
import 'utils/document_scan_helper.dart';
import 'utils/image_helper.dart';
import 'utils/vault_pin_prefs.dart';
import 'vault_family_pages.dart';
import 'business_cards_screen.dart';
import 'widgets/family_expiry_panel.dart';

// ==================== LIGHT VAULT THEME ====================
class AppColors {
  static const Color primary = Color(0xFF4F46E5);
  static const Color secondary = Color(0xFFEEF2FF);
  static const Color accent = Color(0xFF06B6D4);
  static const Color highlight = Color(0xFFEF4444);
  static const Color gold = Color(0xFFF59E0B);
  static const Color teal = Color(0xFF10B981);
  static const Color softPurple = Color(0xFF8B5CF6);
  static const Color cardBg = Colors.white;
  static const Color surfaceLight = Color(0xFFF1F5F9);
  static const Color textPrimary = Color(0xFF1E293B);
  static const Color textSecondary = Color(0xFF64748B);
  static const Color textMuted = Color(0xFF94A3B8);
}

// ==================== MAIN VAULT SCREEN ====================
class VaultScreen extends StatefulWidget {
  const VaultScreen({super.key});
  @override
  State<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends State<VaultScreen>
    with TickerProviderStateMixin {
  List<Map<String, dynamic>> _vaultItems = [];
  List<Map<String, dynamic>> _cards = [];
  List<Map<String, dynamic>> _familyDocs = [];
  List<Map<String, dynamic>> _businessCards = [];

  bool _isLoading = true;
  bool _isLocked = false;
  String? _savedVaultPin;
  final TextEditingController _pinController = TextEditingController();
  String _enteredPin = "";
  bool _pinError = false;
  late AnimationController _lockAnimController;
  late Animation<double> _lockScaleAnim;

  @override
  void initState() {
    super.initState();
    _lockAnimController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);
    _lockScaleAnim = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _lockAnimController, curve: Curves.easeInOut),
    );
    _checkVaultLock();
  }

  @override
  void dispose() {
    _lockAnimController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _checkVaultLock() async {
    _savedVaultPin = await VaultPinPrefs.getPin();
    if (_savedVaultPin != null && _savedVaultPin!.isNotEmpty) {
      setState(() {
        _isLocked = true;
        _isLoading = false;
      });
    } else {
      _loadVaultData();
    }
  }

  Future<void> _loadVaultData() async {
    setState(() => _isLoading = true);
    try {
      _vaultItems = await DatabaseHelper.instance.getVaultItems();
      _cards = await DatabaseHelper.instance.getCards();
      _familyDocs = await DatabaseHelper.instance.queryAllRows('family_vault');
      _businessCards = await DatabaseHelper.instance.getBusinessCards();
    } catch (e) {
      debugPrint("Error loading vault data: $e");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // ==================== PIN DOTS ====================
  Widget _buildPinDots() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(4, (index) {
        final filled = index < _enteredPin.length;
        final error = _pinError && _enteredPin.length == 4;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(horizontal: 10),
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: filled
                ? (error ? Colors.red : const Color(0xFF4F46E5))
                : Colors.grey.shade300,
          ),
        );
      }),
    );
  }

  // ==================== NUMPAD BUTTON ====================
  Widget _buildNumpadButton(String text, {bool isDelete = false}) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact(); // ✅ NOW WORKS
        if (isDelete) {
          if (_enteredPin.isNotEmpty) {
            setState(() {
              _enteredPin = _enteredPin.substring(0, _enteredPin.length - 1);
              _pinError = false;
            });
          }
        } else {
          if (_enteredPin.length < 4) {
            setState(() {
              _enteredPin += text;
              _pinError = false;
            });
            if (_enteredPin.length == 4) {
              Future.delayed(const Duration(milliseconds: 300), () {
                if (_enteredPin == _savedVaultPin) {
                  setState(() => _isLocked = false);
                  _loadVaultData();
                } else {
                  setState(() => _pinError = true);
                  HapticFeedback.heavyImpact(); // ✅ NOW WORKS
                  Future.delayed(const Duration(milliseconds: 800), () {
                    setState(() {
                      _enteredPin = "";
                      _pinError = false;
                    });
                  });
                }
              });
            }
          }
        }
      },
      child: Material(
        color: Colors.white,
        shape: const CircleBorder(),
        elevation: 1,
        child: Container(
          width: 72,
          height: 72,
          alignment: Alignment.center,
          child: isDelete
              ? Icon(Icons.backspace_outlined,
                  color: Colors.grey.shade700, size: 26)
              : Text(
                  text,
                  style: TextStyle(
                    color: Colors.grey.shade900,
                    fontSize: 26,
                    fontWeight: FontWeight.w500,
                  ),
                ),
        ),
      ),
    );
  }

  // ==================== LOCK SCREEN ====================
  Widget _buildLockScreen() {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 48),
            _ScaleAnimatedBuilder(
              animation: _lockScaleAnim,
              builder: (context, child) => Transform.scale(
                scale: _lockScaleAnim.value,
                child: Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF4F46E5).withOpacity(0.12),
                  ),
                  child: const Icon(
                    Icons.lock_outline_rounded,
                    size: 44,
                    color: Color(0xFF4F46E5),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Vault',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1E1E2E),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Enter your 4-digit PIN',
              style: TextStyle(fontSize: 15, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 36),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: _buildPinDots(),
              ),
            if (_pinError)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text(
                  'Incorrect PIN, try again',
                  style: TextStyle(
                    color: Colors.red,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 36),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildNumpadButton("1"),
                        _buildNumpadButton("2"),
                        _buildNumpadButton("3"),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildNumpadButton("4"),
                        _buildNumpadButton("5"),
                        _buildNumpadButton("6"),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildNumpadButton("7"),
                        _buildNumpadButton("8"),
                        _buildNumpadButton("9"),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        const SizedBox(width: 75, height: 75),
                        _buildNumpadButton("0"),
                        _buildNumpadButton("", isDelete: true),
                      ],
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  // ==================== DASHBOARD FOLDER CARD ====================
  Widget _buildDashboardFolder({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color accent,
    required int count,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: IntrinsicHeight(
              child: Row(
                children: [
                  Container(
                    width: 5,
                    decoration: BoxDecoration(
                      color: accent,
                      borderRadius: const BorderRadius.horizontal(
                        left: Radius.circular(16),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 16, 12, 16),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: accent.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(icon, color: accent, size: 24),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF1E293B),
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  subtitle,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: AppTheme.surface,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: Colors.grey.shade200),
                            ),
                            child: Text(
                              "$count",
                              style: TextStyle(
                                color: Colors.grey.shade800,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(Icons.chevron_right_rounded,
                              color: Colors.grey.shade400),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ==================== STAT CARD ====================
  Widget _buildStatCard({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppColors.textMuted.withOpacity(0.1),
          ),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 8),
            Text(
              value,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: AppColors.textMuted,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== PASSWORDS SHEET ====================
  void _openPasswordsSheet() {
    _showCustomSheet(
      "Secure Passwords",
      const LinearGradient(
        colors: [Color(0xFFFF6B35), Color(0xFFF7931E)],
      ),
      Icons.lock_rounded,
      () => _showAddPasswordDialog(),
      _vaultItems.isEmpty
          ? _buildEmptyState(
              Icons.password_rounded,
              "No Passwords Saved",
              "Tap + to add your first secure password",
            )
          : ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              itemCount: _vaultItems.length,
              itemBuilder: (c, i) {
                final item = _vaultItems[i];
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: AppColors.cardBg,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: AppColors.textMuted.withOpacity(0.1),
                    ),
                  ),
                  child: Theme(
                    data: Theme.of(context).copyWith(
                      dividerColor: Colors.transparent,
                    ),
                    child: ExpansionTile(
                      tilePadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 4),
                      leading: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFFF6B35), Color(0xFFF7931E)],
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.lock,
                            color: Colors.white, size: 20),
                      ),
                      title: Text(
                        item['title'],
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                          fontSize: 15,
                        ),
                      ),
                      subtitle: Text(
                        item['user_id'] ?? 'No username',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textMuted,
                        ),
                      ),
                      trailing: const Icon(Icons.expand_more,
                          color: AppColors.textMuted),
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          margin: const EdgeInsets.symmetric(horizontal: 8),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceLight.withOpacity(0.5),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildDetailRow(
                                  "Username",
                                  item['user_id'] ?? 'N/A',
                                  Icons.person_outline),
                              const SizedBox(height: 12),
                              _buildDetailRow("Password", item['content'] ?? '',
                                  Icons.key_outlined),
                              const SizedBox(height: 16),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  _buildActionButton(
                                    icon: Icons.edit_outlined,
                                    label: "Edit",
                                    color: AppColors.teal,
                                    onTap: () {
                                      Navigator.pop(context);
                                      _showAddPasswordDialog(editNote: item);
                                    },
                                  ),
                                  const SizedBox(width: 10),
                                  _buildActionButton(
                                    icon: Icons.delete_outline,
                                    label: "Delete",
                                    color: AppColors.highlight,
                                    onTap: () async {
                                      await DatabaseHelper.instance
                                          .delete('vault_items', item['id']);
                                      _loadVaultData();
                                      Navigator.pop(context);
                                    },
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }

  Widget _buildDetailRow(String label, String value, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: AppColors.textMuted, size: 18),
        const SizedBox(width: 10),
        Text(
          "$label: ",
          style: TextStyle(
            color: AppColors.textMuted,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
        Expanded(
          child: SelectableText(
            value,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                  color: color, fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== BANK CARDS SHEET ====================
  void _openBankCardsSheet() {
    _showCustomSheet(
      "Bank Cards",
      const LinearGradient(
        colors: [Color(0xFF4A90D9), Color(0xFF1E88E5)],
      ),
      Icons.credit_card_rounded,
      () => _showAddCardDialog(),
      _cards.isEmpty
          ? _buildEmptyState(
              Icons.credit_card_rounded,
              "No Cards Saved",
              "Tap + to add your first bank card",
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _cards.length,
              itemBuilder: (c, i) {
                final card = _cards[i];
                return _buildBankCard(card);
              },
            ),
    );
  }

  Widget _buildBankCard(Map<String, dynamic> card) {
    List<LinearGradient> cardGradients = [
      const LinearGradient(colors: [Color(0xFF1A237E), Color(0xFF283593)]),
      const LinearGradient(colors: [Color(0xFFB71C1C), Color(0xFFC62828)]),
      const LinearGradient(colors: [Color(0xFF004D40), Color(0xFF00695C)]),
      const LinearGradient(colors: [Color(0xFFE65100), Color(0xFFEF6C00)]),
      const LinearGradient(colors: [Color(0xFF4A148C), Color(0xFF6A1B9A)]),
    ];
    int gradientIndex = card['card_type'] == 'MasterCard'
        ? 3
        : (card['card_type'] == 'Visa'
            ? 0
            : (card['card_type'] == 'PayPak' ? 2 : 4));
    if (gradientIndex >= cardGradients.length) gradientIndex = 1;

    return GestureDetector(
      onTap: () {
        Navigator.pop(context);
        _viewDetailsDialog(
          "Card Details",
          card,
          () => _showAddCardDialog(editCard: card),
          'cards',
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 20),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: cardGradients[gradientIndex],
          boxShadow: [
            BoxShadow(
              color: cardGradients[gradientIndex].colors.first.withOpacity(0.4),
              blurRadius: 25,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  card['card_type'] ?? "Card",
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 1,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    card['card_type'] == 'MasterCard'
                        ? Icons.credit_card
                        : (card['card_type'] == 'Visa'
                            ? Icons.payment
                            : Icons.credit_card_rounded),
                    color: Colors.white70,
                    size: 20,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 30),
            Text(
              card['card_number'] == ''
                  ? "•••• •••• •••• ••••"
                  : _formatCardNumber(card['card_number']),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w500,
                letterSpacing: 3,
              ),
            ),
            const SizedBox(height: 25),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "CARD HOLDER",
                      style: TextStyle(
                        color: Colors.white38,
                        fontSize: 9,
                        letterSpacing: 1.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      card['card_holder'] == ''
                          ? "FULL NAME"
                          : card['card_holder'],
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text(
                      "EXPIRES",
                      style: TextStyle(
                        color: Colors.white38,
                        fontSize: 9,
                        letterSpacing: 1.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      card['expiry'] == '' ? "MM/YY" : card['expiry'],
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatCardNumber(String number) {
    String clean = number.replaceAll(RegExp(r'\s+'), '');
    String formatted = '';
    for (int i = 0; i < clean.length && i < 16; i++) {
      if (i > 0 && i % 4 == 0) formatted += ' ';
      formatted += clean[i];
    }
    return formatted;
  }

  // ==================== FAMILY VAULT (push navigation) ====================
  void _openFamilyVaultPage() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FamilyVaultHubPage(
          openEditor: ({editDoc, prefilledName}) => _showAddFamilyDocDialog(
            editDoc: editDoc,
            prefilledName: prefilledName,
          ),
        ),
      ),
    ).then((_) => _loadVaultData());
  }

  void _openBusinessCardsPage() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const BusinessCardsPage()),
    ).then((_) => _loadVaultData());
  }

  // Legacy sheet kept unused — superseded by FamilyVaultHubPage.
  void _openFamilyVaultSheet() => _openFamilyVaultPage();

  void _showMemberDocs(String name) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FamilyMemberDocsPage(
          memberName: name,
          openEditor: ({editDoc, prefilledName}) => _showAddFamilyDocDialog(
            editDoc: editDoc,
            prefilledName: prefilledName ?? name,
          ),
          onChanged: _loadVaultData,
        ),
      ),
    ).then((_) => _loadVaultData());
  }

  // ==================== EMPTY STATE ====================
  Widget _buildEmptyState(IconData icon, String title, String subtitle) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppColors.surfaceLight.withOpacity(0.5),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 50, color: AppColors.textMuted),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textMuted,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== CUSTOM BOTTOM SHEET ====================
  void _showCustomSheet(
    String title,
    Gradient gradient,
    IconData icon,
    VoidCallback onAdd,
    Widget content,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        height: MediaQuery.of(ctx).size.height * 0.85,
        decoration: const BoxDecoration(
          color: AppColors.primary,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              decoration: BoxDecoration(
                gradient: gradient,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      Navigator.pop(ctx);
                      onAdd();
                    },
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.add_rounded,
                          color: Colors.white, size: 24),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(child: content),
          ],
        ),
      ),
    );
  }

  // ==================== DIALOGS ====================
  void _showAddPasswordDialog({Map<String, dynamic>? editNote}) {
    showDialog(
      context: context,
      builder: (c) => AddPasswordWidget(
        editNote: editNote,
        onSave: (data) async {
          if (editNote == null) {
            await DatabaseHelper.instance.insert('vault_items', data);
          } else {
            await DatabaseHelper.instance
                .update('vault_items', editNote['id'], data);
          }
          _loadVaultData();
        },
      ),
    );
  }

  void _showAddCardDialog({Map<String, dynamic>? editCard}) {
    showDialog(
      context: context,
      builder: (c) => AddCardWidget(
        existingTypes: _cards.map((e) => e['card_type'].toString()).toList(),
        editCard: editCard,
        onSave: (data) async {
          editCard == null
              ? await DatabaseHelper.instance.insert('cards', data)
              : await DatabaseHelper.instance
                  .update('cards', editCard['id'], data);
          _loadVaultData();
        },
      ),
    );
  }

  Future<void> _showAddFamilyDocDialog(
      {Map<String, dynamic>? editDoc, String? prefilledName}) async {
    await showDialog(
      context: context,
      builder: (c) => AddFamilyDocWidget(
        existingTypes:
            _familyDocs.map((e) => e['doc_type'].toString()).toList(),
        editDoc: editDoc,
        prefilledName: prefilledName,
        onSave: (data) async {
          editDoc == null
              ? await DatabaseHelper.instance.insert('family_vault', data)
              : await DatabaseHelper.instance
                  .update('family_vault', editDoc['id'], data);
          await _loadVaultData();
        },
      ),
    );
    await _loadVaultData();
  }

  void _viewDocDetails(Map<String, dynamic> doc) {
    List<String> imgs = _parseImages(doc);
    _viewDetailsDialog(
      doc['doc_type'],
      doc,
      () => _showAddFamilyDocDialog(editDoc: doc),
      'family_vault',
      extraActions: [
        GestureDetector(
          onTap: () async {
            String txt =
                "Title: ${doc['title'] ?? ''}\nName: ${doc['member_name']}\nType: ${doc['doc_type']}\nNo: ${doc['doc_number']}\nExp: ${doc['expiry_date']?.split('T')[0] ?? 'N/A'}";
            List<XFile> xImgs = imgs.map((path) => XFile(path)).toList();
            xImgs.isNotEmpty
                ? await Share.shareXFiles(xImgs, text: txt)
                : await Share.share(txt);
          },
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.teal.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.share_rounded,
                color: AppColors.teal, size: 20),
          ),
        ),
      ],
      children: [
        _buildInfoTile(Icons.title_rounded, "Title",
            (doc['title']?.toString().trim().isNotEmpty == true)
                ? doc['title'].toString()
                : (doc['doc_type'] ?? '—').toString()),
        _buildInfoTile(Icons.person_outline, "Member", doc['member_name']),
        _buildInfoTile(Icons.badge_outlined, "Type", doc['doc_type']),
        _buildInfoTile(Icons.numbers_rounded, "Number", doc['doc_number']),
        _buildInfoTile(Icons.calendar_today_rounded, "Expiry",
            doc['expiry_date']?.split('T')[0] ?? 'N/A',
            color: AppColors.highlight),
        const SizedBox(height: 16),
        if (imgs.isNotEmpty) ...[
          const Text(
            "Attached Images",
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: imgs.map((path) => _buildImageThumbnail(path)).toList(),
          ),
        ],
      ],
    );
  }

  Widget _buildInfoTile(IconData icon, String label, String value,
      {Color? color}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceLight.withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: color ?? AppColors.textMuted, size: 20),
          const SizedBox(width: 12),
          Text(
            "$label: ",
            style: TextStyle(
              color: AppColors.textMuted,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: color ?? AppColors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _viewDetailsDialog(
    String title,
    Map<String, dynamic> item,
    VoidCallback onEdit,
    String table, {
    List<Widget>? extraActions,
    List<Widget>? children,
  }) {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: AppColors.textMuted.withOpacity(0.2),
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                  fontSize: 18,
                ),
              ),
            ),
            ...?extraActions,
            GestureDetector(
              onTap: () {
                Navigator.pop(c);
                onEdit();
              },
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.teal.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.edit_rounded,
                    color: AppColors.teal, size: 18),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children ??
                [
                  _buildInfoTile(
                      Icons.person_outline, "Holder", item['card_holder']),
                  _buildInfoTile(
                      Icons.credit_card, "Number", item['card_number']),
                  _buildInfoTile(
                      Icons.calendar_today_rounded, "Expiry", item['expiry']),
                  _buildInfoTile(Icons.lock_outline, "CVV", item['cvv']),
                  if (item['front_image'] != null)
                    _buildImageThumbnail(item['front_image'], label: "Front"),
                  if (item['back_image'] != null)
                    _buildImageThumbnail(item['back_image'], label: "Back"),
                ],
          ),
        ),
        actions: [
          GestureDetector(
            onTap: () async {
              await DatabaseHelper.instance.delete(table, item['id']);
              _loadVaultData();
              Navigator.pop(c);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.highlight.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.highlight.withOpacity(0.3)),
              ),
              child: const Text(
                "Delete",
                style: TextStyle(
                    color: AppColors.highlight, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          GestureDetector(
            onTap: () => Navigator.pop(c),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.surfaceLight,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                "Close",
                style: TextStyle(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImageThumbnail(String path, {String? label}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              label,
              style: TextStyle(
                color: AppColors.textMuted,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        GestureDetector(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => FullScreenImageViewer(imagePath: path),
            ),
          ),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppColors.textMuted.withOpacity(0.2),
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(11),
              child: Image.file(
                File(path),
                width: 90,
                height: 90,
                fit: BoxFit.cover,
              ),
            ),
          ),
        ),
      ],
    );
  }

  List<String> _parseImages(Map<String, dynamic> doc) {
    if (doc['images'] != null &&
        doc['images'] != '' &&
        doc['images'] != 'null') {
      try {
        return List<String>.from(jsonDecode(doc['images']));
      } catch (_) {}
    }
    return [
      if (doc['front_image'] != null) doc['front_image'],
      if (doc['back_image'] != null) doc['back_image'],
    ];
  }

  // ==================== MAIN BUILD ====================
  @override
  Widget build(BuildContext context) {
    if (_isLocked) return _buildLockScreen();

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: _isLoading
            ? const Center(
                child: CircularProgressIndicator(
                  color: AppColors.primary,
                ),
              )
              : CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppTheme.primary.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: const Icon(Icons.shield_rounded,
                                  color: AppTheme.primary, size: 24),
                            ),
                            const SizedBox(width: 14),
                            const Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "Secure Vault",
                                  style: TextStyle(
                                    color: Color(0xFF1E293B),
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  "Passwords, cards & family docs",
                                  style: TextStyle(
                                    color: Color(0xFF64748B),
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                            const Spacer(),
                            InkWell(
                              onTap: () => FamilyExpiryCenter.show(context),
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: AppColors.surfaceLight,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color:
                                        AppColors.textMuted.withOpacity(0.15),
                                  ),
                                ),
                                child: const Icon(
                                  Icons.notifications_none_rounded,
                                  color: AppColors.textSecondary,
                                  size: 22,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SliverToBoxAdapter(child: SizedBox(height: 24)),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Row(
                          children: [
                            _buildStatCard(
                              label: "Passwords",
                              value: "${_vaultItems.length}",
                              icon: Icons.lock_rounded,
                              color: const Color(0xFFFF6B35),
                            ),
                            const SizedBox(width: 12),
                            _buildStatCard(
                              label: "Cards",
                              value: "${_cards.length}",
                              icon: Icons.credit_card_rounded,
                              color: const Color(0xFF4A90D9),
                            ),
                            const SizedBox(width: 12),
                            _buildStatCard(
                              label: "Documents",
                              value: "${_familyDocs.length}",
                              icon: Icons.folder_rounded,
                              color: AppColors.softPurple,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SliverToBoxAdapter(child: SizedBox(height: 28)),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: const Text(
                          "CATEGORIES",
                          style: TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 2,
                          ),
                        ),
                      ),
                    ),
                    const SliverToBoxAdapter(child: SizedBox(height: 14)),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: _buildDashboardFolder(
                          title: "Family Documents",
                          subtitle: "Identity, Education, Medical & more",
                          icon: Icons.folder_shared_rounded,
                          accent: AppTheme.primary,
                          count: _familyDocs.length,
                          onTap: _openFamilyVaultPage,
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: _buildDashboardFolder(
                          title: "Business Cards",
                          subtitle: "Scan, auto-title & master search",
                          icon: Icons.badge_rounded,
                          accent: const Color(0xFF0D9488),
                          count: _businessCards.length,
                          onTap: _openBusinessCardsPage,
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: _buildDashboardFolder(
                          title: "Bank Cards",
                          subtitle: "Visa, MasterCard, PayPak & more",
                          icon: Icons.credit_card_rounded,
                          accent: const Color(0xFF3B82F6),
                          count: _cards.length,
                          onTap: _openBankCardsSheet,
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: _buildDashboardFolder(
                          title: "Secure Passwords",
                          subtitle: "Accounts, Emails & App passwords",
                          icon: Icons.password_rounded,
                          accent: const Color(0xFFF59E0B),
                          count: _vaultItems.length,
                          onTap: _openPasswordsSheet,
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Container(
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            gradient: LinearGradient(
                              colors: [
                                AppColors.teal.withOpacity(0.1),
                                AppColors.accent.withOpacity(0.1),
                              ],
                            ),
                            border: Border.all(
                              color: AppColors.teal.withOpacity(0.2),
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: AppColors.teal.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(Icons.verified_user_rounded,
                                    color: AppColors.teal, size: 22),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      "PIN-protected local vault",
                                      style: TextStyle(
                                        color: AppColors.textPrimary,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      "Locked with your Vault PIN on this device (not cloud E2E)",
                                      style: TextStyle(
                                        color: AppColors.textMuted,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SliverToBoxAdapter(child: SizedBox(height: 20)),
                  ],
                ),
      ),
    );
  }
}

// ==================== RENAMED ANIMATED BUILDER (avoids Flutter conflict) ====================
class _ScaleAnimatedBuilder extends AnimatedWidget {
  final Widget Function(BuildContext context, Widget? child) builder;
  final Widget? child;

  const _ScaleAnimatedBuilder({
    required Animation<double> animation,
    required this.builder,
    this.child,
  }) : super(listenable: animation);

  @override
  Widget build(BuildContext context) {
    return builder(context, child);
  }
}

// ==================== ADD PASSWORD WIDGET ====================
class AddPasswordWidget extends StatelessWidget {
  final Map<String, dynamic>? editNote;
  final Function(Map<String, dynamic>) onSave;
  const AddPasswordWidget({super.key, this.editNote, required this.onSave});

  @override
  Widget build(BuildContext context) {
    final tC = TextEditingController(text: editNote?['title'] ?? '');
    final uC = TextEditingController(text: editNote?['user_id'] ?? '');
    final pC = TextEditingController(text: editNote?['content'] ?? '');

    return AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: AppColors.textMuted.withOpacity(0.2)),
      ),
      title: Text(
        editNote == null ? "Add Password" : "Edit Password",
        style: const TextStyle(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.bold,
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildDarkTextField(
              tC, "Account Name (e.g. Gmail)", Icons.label_outline),
          const SizedBox(height: 14),
          _buildDarkTextField(uC, "User ID / Email", Icons.person_outline),
          const SizedBox(height: 14),
          _buildDarkTextField(pC, "Password", Icons.lock_outline),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("Cancel",
              style: TextStyle(color: AppColors.textMuted)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.highlight,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          onPressed: () {
            if (tC.text.isNotEmpty) {
              onSave(
                  {'title': tC.text, 'user_id': uC.text, 'content': pC.text});
              Navigator.pop(context);
            }
          },
          child: const Text("Save", style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}

// ==================== SHARED DARK TEXT FIELD ====================
// ✅ FIXED: Added isNumber and isObscure parameters
Widget _buildDarkTextField(
  TextEditingController controller,
  String label,
  IconData icon, {
  bool isNumber = false, // ✅ ADDED
  bool isObscure = false, // ✅ ADDED
  String? hint,
}) {
  return TextField(
    controller: controller,
    style: const TextStyle(color: AppColors.textPrimary),
    obscureText: isObscure,
    keyboardType: isNumber ? TextInputType.number : TextInputType.text,
    textCapitalization:
        isNumber || isObscure ? TextCapitalization.none : TextCapitalization.words,
    decoration: InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: TextStyle(color: AppColors.textMuted),
      hintStyle: TextStyle(color: AppColors.textMuted.withOpacity(0.7), fontSize: 13),
      prefixIcon: Icon(icon, color: AppColors.textMuted, size: 20),
      filled: true,
      fillColor: AppColors.surfaceLight.withOpacity(0.5),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppColors.textMuted.withOpacity(0.2)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppColors.textMuted.withOpacity(0.2)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.highlight, width: 1.5),
      ),
    ),
  );
}

// ==================== ADD CARD WIDGET ====================
class AddCardWidget extends StatefulWidget {
  final List<String> existingTypes;
  final Map<String, dynamic>? editCard;
  final Function(Map<String, dynamic>) onSave;
  const AddCardWidget({
    super.key,
    required this.existingTypes,
    this.editCard,
    required this.onSave,
  });
  @override
  State<AddCardWidget> createState() => _AddCardWidgetState();
}

class _AddCardWidgetState extends State<AddCardWidget> {
  late TextEditingController holderC, numC, expC, cvvC;
  late String type;
  List<String> types = [];
  String? frontImg, backImg;

  @override
  void initState() {
    super.initState();
    holderC =
        TextEditingController(text: widget.editCard?['card_holder'] ?? '');
    numC = TextEditingController(text: widget.editCard?['card_number'] ?? '');
    expC = TextEditingController(text: widget.editCard?['expiry'] ?? '');
    cvvC = TextEditingController(text: widget.editCard?['cvv'] ?? '');
    types = {
      "Visa",
      "MasterCard",
      "PayPak",
      "UnionPay",
      ...widget.existingTypes
    }.toList();
    type = widget.editCard?['card_type'] ?? "Visa";
    if (!types.contains(type)) types.add(type);
    frontImg = widget.editCard?['front_image'];
    backImg = widget.editCard?['back_image'];
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: AppColors.textMuted.withOpacity(0.2)),
      ),
      title: Text(
        widget.editCard == null ? "Add Bank Card" : "Edit Bank Card",
        style: const TextStyle(
            color: AppColors.textPrimary, fontWeight: FontWeight.bold),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              value: type,
              items: types
                  .map((e) => DropdownMenuItem(
                      value: e,
                      child: Text(e,
                          style:
                              const TextStyle(color: AppColors.textPrimary))))
                  .toList(),
              onChanged: (v) => setState(() => type = v.toString()),
              decoration: InputDecoration(
                labelText: "Card Type",
                labelStyle: TextStyle(color: AppColors.textMuted),
                filled: true,
                fillColor: AppColors.surfaceLight.withOpacity(0.5),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                      BorderSide(color: AppColors.textMuted.withOpacity(0.2)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                      BorderSide(color: AppColors.textMuted.withOpacity(0.2)),
                ),
              ),
              dropdownColor: AppColors.secondary,
            ),
            const SizedBox(height: 12),
            _buildDarkTextField(
                holderC, "Card Holder Name", Icons.person_outline),
            const SizedBox(height: 12),
            // ✅ FIXED: Now uses isNumber parameter
            _buildDarkTextField(numC, "Card Number", Icons.credit_card,
                isNumber: true),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                    child: _buildDarkTextField(
                        expC, "Expiry", Icons.calendar_today)),
                const SizedBox(width: 10),
                // ✅ FIXED: Now uses isObscure parameter
                Expanded(
                    child: _buildDarkTextField(cvvC, "CVV", Icons.lock,
                        isObscure: true)),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildImagePickerButton(
                  label: "Front",
                  hasImage: frontImg != null,
                  onTap: () async {
                    final p = await _pickImage();
                    if (p != null) setState(() => frontImg = p);
                  },
                ),
                _buildImagePickerButton(
                  label: "Back",
                  hasImage: backImg != null,
                  onTap: () async {
                    final p = await _pickImage();
                    if (p != null) setState(() => backImg = p);
                  },
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("Cancel",
              style: TextStyle(color: AppColors.textMuted)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.highlight,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          onPressed: () {
            widget.onSave({
              'card_holder': holderC.text,
              'card_number': numC.text,
              'expiry': expC.text,
              'cvv': cvvC.text,
              'card_type': type,
              'color': 0xFF3F51B5,
              'front_image': frontImg,
              'back_image': backImg,
            });
            Navigator.pop(context);
          },
          child: const Text("Save", style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }

  Widget _buildImagePickerButton({
    required String label,
    required bool hasImage,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          color: hasImage
              ? AppColors.teal.withOpacity(0.15)
              : AppColors.surfaceLight.withOpacity(0.5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: hasImage
                ? AppColors.teal.withOpacity(0.4)
                : AppColors.textMuted.withOpacity(0.2),
          ),
        ),
        child: Column(
          children: [
            Icon(
              hasImage ? Icons.check_circle_rounded : Icons.add_a_photo_rounded,
              color: hasImage ? AppColors.teal : AppColors.textMuted,
              size: 26,
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                color: hasImage ? AppColors.teal : AppColors.textMuted,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<String?> _pickImage() async {
    final path = await DocumentScanHelper.pickDocumentImage(context);
    if (path == null) return null;
    return ImageHelper.copyToAppStorage(path, 'vault_card');
  }
}

// ==================== ADD FAMILY DOC WIDGET ====================
class AddFamilyDocWidget extends StatefulWidget {
  final List<String> existingTypes;
  final Map<String, dynamic>? editDoc;
  final String? prefilledName;
  final Function(Map<String, dynamic>) onSave;
  const AddFamilyDocWidget({
    super.key,
    required this.existingTypes,
    this.editDoc,
    this.prefilledName,
    required this.onSave,
  });
  @override
  State<AddFamilyDocWidget> createState() => _AddFamilyDocWidgetState();
}

class _AddFamilyDocWidgetState extends State<AddFamilyDocWidget> {
  static const _addTypeSentinel = '__add_new_doc_type__';
  late TextEditingController nameC, titleC, numC;
  late String docType;
  List<String> types = [];
  DateTime? expiry;
  List<String> docImages = [];

  @override
  void initState() {
    super.initState();
    nameC = TextEditingController(
        text: widget.editDoc?['member_name'] ?? widget.prefilledName ?? '');
    titleC = TextEditingController(
        text: widget.editDoc?['title']?.toString() ?? '');
    numC = TextEditingController(text: widget.editDoc?['doc_number'] ?? '');
    types = {
      "Identity",
      "Education",
      "Medical",
      "Hospital MR",
      "Finance",
      "Other",
      ...widget.existingTypes
    }.toList();
    docType = widget.editDoc?['doc_type'] ?? "Identity";
    if (!types.contains(docType)) types.add(docType);
    expiry = widget.editDoc?['expiry_date'] != null
        ? DateTime.parse(widget.editDoc!['expiry_date'])
        : null;
    if (widget.editDoc != null &&
        widget.editDoc!['images'] != null &&
        widget.editDoc!['images'] != 'null') {
      try {
        docImages = List<String>.from(jsonDecode(widget.editDoc!['images']));
      } catch (_) {}
    }
  }

  bool get _isMedicalType {
    final t = docType.toLowerCase();
    return t == 'medical' ||
        t == 'hospital mr' ||
        t.contains('hospital') ||
        t.contains('mr');
  }

  String get _numberLabel => _isMedicalType
      ? 'MR / Card Number'
      : 'Doc Number (CNIC, etc.)';

  String get _titleHint => _isMedicalType
      ? 'e.g. Dow Hospital, Aga Khan Hospital'
      : 'e.g. CNIC, Passport, Degree';

  Future<void> _addNewDocType() async {
    final typeC = TextEditingController();
    final created = await showDialog<String>(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: const Text('New document type'),
        content: TextField(
          controller: typeC,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Type name',
            hintText: 'e.g. Insurance, Visa, Lab Report',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (v) {
            final name = v.trim();
            if (name.isNotEmpty) Navigator.pop(dCtx, name);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final name = typeC.text.trim();
              if (name.isEmpty) return;
              Navigator.pop(dCtx, name);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (created == null || created.isEmpty) return;
    final exists = types.any((t) => t.toLowerCase() == created.toLowerCase());
    if (exists) {
      final existing = types.firstWhere(
          (t) => t.toLowerCase() == created.toLowerCase());
      setState(() => docType = existing);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Type "$existing" already exists'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }
    setState(() {
      types.add(created);
      docType = created;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: AppColors.textMuted.withOpacity(0.2)),
      ),
      title: Text(
        widget.editDoc == null ? "Add Family Document" : "Edit Document",
        style: const TextStyle(
            color: AppColors.textPrimary, fontWeight: FontWeight.bold),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDarkTextField(nameC, "Member Name", Icons.person_outline),
            const SizedBox(height: 12),
            _buildDarkTextField(
              titleC,
              "Title (hospital / document name)",
              Icons.title_rounded,
              hint: _titleHint,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: types.contains(docType) ? docType : null,
              items: [
                ...types.map((e) => DropdownMenuItem(
                      value: e,
                      child: Text(e,
                          style:
                              const TextStyle(color: AppColors.textPrimary)),
                    )),
                const DropdownMenuItem(
                  value: _addTypeSentinel,
                  child: Row(
                    children: [
                      Icon(Icons.add_circle_outline,
                          size: 20, color: AppColors.primary),
                      SizedBox(width: 8),
                      Text(
                        'Add new type',
                        style: TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              onChanged: (v) async {
                if (v == _addTypeSentinel) {
                  await _addNewDocType();
                } else if (v != null) {
                  setState(() => docType = v);
                }
              },
              decoration: InputDecoration(
                labelText: "Document Type",
                labelStyle: TextStyle(color: AppColors.textMuted),
                filled: true,
                fillColor: AppColors.surfaceLight.withOpacity(0.5),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                      BorderSide(color: AppColors.textMuted.withOpacity(0.2)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                      BorderSide(color: AppColors.textMuted.withOpacity(0.2)),
                ),
              ),
              dropdownColor: AppColors.secondary,
            ),
            const SizedBox(height: 12),
            _buildDarkTextField(
                numC, _numberLabel, Icons.numbers_rounded),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () async {
                DateTime? picked = await showDatePicker(
                  context: context,
                  initialDate: DateTime.now(),
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2050),
                );
                if (picked != null) setState(() => expiry = picked);
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                decoration: BoxDecoration(
                  color: AppColors.surfaceLight.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(12),
                  border:
                      Border.all(color: AppColors.textMuted.withOpacity(0.2)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.calendar_today_rounded,
                        color: AppColors.textMuted, size: 20),
                    const SizedBox(width: 12),
                    Text(
                      expiry == null
                          ? "Select Expiry Date"
                          : "Expiry: ${DateFormat('yyyy-MM-dd').format(expiry!)}",
                      style: TextStyle(
                        color: expiry == null
                            ? AppColors.textMuted
                            : AppColors.textPrimary,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              "IMAGES (UP TO 10)",
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: AppColors.softPurple,
                fontSize: 11,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                ...docImages.map((path) => Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.file(File(path),
                              width: 65, height: 65, fit: BoxFit.cover),
                        ),
                        Positioned(
                          right: 0,
                          top: 0,
                          child: GestureDetector(
                            onTap: () => setState(() => docImages.remove(path)),
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: const BoxDecoration(
                                  color: AppColors.highlight,
                                  shape: BoxShape.circle),
                              child: const Icon(Icons.close,
                                  size: 12, color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    )),
                if (docImages.length < 10)
                  GestureDetector(
                    onTap: () async {
                      final added =
                          await DocumentScanHelper.pickMultipleDocumentImages(
                        context,
                        maxCount: 10,
                        currentCount: docImages.length,
                      );
                      if (added.isEmpty) return;
                      final saved =
                          await ImageHelper.persistPaths(added, 'vault_doc');
                      if (mounted) setState(() => docImages.addAll(saved));
                    },
                    child: Container(
                      width: 65,
                      height: 65,
                      decoration: BoxDecoration(
                        color: AppColors.surfaceLight.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: AppColors.softPurple.withOpacity(0.3),
                            strokeAlign: 1),
                      ),
                      child: const Icon(Icons.document_scanner_outlined,
                          color: AppColors.softPurple, size: 24),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("Cancel",
              style: TextStyle(color: AppColors.textMuted)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.highlight,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          onPressed: () {
            if (nameC.text.isNotEmpty) {
              widget.onSave({
                'member_name': nameC.text.trim(),
                'title': titleC.text.trim(),
                'doc_type': docType,
                'doc_number': numC.text.trim(),
                'expiry_date': expiry?.toIso8601String(),
                'images': jsonEncode(docImages),
                'timestamp': DateTime.now().toIso8601String(),
              });
              Navigator.pop(context);
            }
          },
          child: const Text("Save", style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}

// ==================== FULL SCREEN IMAGE VIEWER ====================
class FullScreenImageViewer extends StatelessWidget {
  final String imagePath;
  const FullScreenImageViewer({super.key, required this.imagePath});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 1.0,
          maxScale: 5.0,
          child: Image.file(File(imagePath)),
        ),
      ),
    );
  }
}
