import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

void showSheikhBioDialog(BuildContext context) {
  showDialog(
    context: context,
    barrierColor: Colors.black.withOpacity(0.7),
    builder: (context) {
      return Directionality(
        textDirection: TextDirection.rtl,
        child: Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 20),
          child: Container(
            constraints: const BoxConstraints(
              maxWidth: 420,
              maxHeight: 500,
            ),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.cardDark,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: AppColors.primaryTeal.withOpacity(0.4),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.4),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'من هو الشيخ أبو الحسن خوجلي إبراهيم',
                        style: TextStyle(
                          color: AppColors.mainText,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: Icon(
                        Icons.close,
                        color: AppColors.secondaryText,
                        size: 20,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Divider(
                  color: AppColors.cardGradientStart.withOpacity(0.4),
                ),
                const SizedBox(height: 10),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _BioParagraph(
                          'عضو المجلس العلمي بجماعة أنصار السنة المحمدية بالسودان.',
                        ),
                        _BioParagraph(
                          'يُعرف بعنايته بالقرآن والسنة وعلوم العقيدة والفقه، وبجهوده في تدريس العلم الشرعي وتعليمه لطلاب العلم. وقد تلقى العلم عن عدد من علماء السودان والمملكة العربية السعودية، ومن أبرزهم الشيخ عبد المحسن بن حمد العباد، والشيخ عبد الرزاق البدر، والدكتور إبراهيم الرحيلي، والشيخ يحيى بن عبد العزيز اليحيى، وغيرهم.',
                        ),
                        _BioParagraph(
                          'وله عدد من المؤلفات والرسائل العلمية، من أبرزها: القول المسدد، والنصيحة، وإثبات علو الله على خلقه، ومائة حديث في أركان الإسلام، ومائة حديث في أركان الإيمان، وتذكير الأتقياء بحرمة سفك الدماء، والمخالفون لأهل السنة والجماعة في الإيمان.',
                        ),
                        _BioParagraph(
                          'كما له دروس ودورات علمية في العقيدة والفقه والفرائض وغيرها، ومن أبرزها: شرح العقيدة الطحاوية، وشرح العقيدة الواسطية، وشرح سلم الوصول، وشرح القواعد المثلى، وشرح القواعد الفقهية، وشرح الرحبية، وشرح تقريب التدمرية، وشرح تلخيص الحموية، إلى جانب دروسه في التوحيد والتفسير والسيرة.',
                        ),
                        _BioParagraph(
                          'وقد أسهم في تعليم طلاب العلم وإقامة الدورات العلمية وحلقات تحفيظ القرآن، ولا يزال يبذل جهده في تعليم الناس وإفادتهم.',
                        ),
                        _BioParagraph(
                          'نسأل الله أن يحفظه وينفع بعلمه، ويجزيه خير الجزاء على ما يقدمه في خدمة كتاب الله وسنة رسوله ﷺ وتعليم طلاب العلم.',
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryTeal,
                      foregroundColor: AppColors.background,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    child: const Text(
                      'إغلاق',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _BioParagraph extends StatelessWidget {
  final String text;

  const _BioParagraph(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        '• $text',
        style: TextStyle(
          color: AppColors.lightText,
          fontSize: 12,
          height: 1.6,
        ),
      ),
    );
  }
}
