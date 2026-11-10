class AppConstants {
  static const String appName = 'HPLeila';
  static const String appNameEn = 'HPLeila';
  static const String version = '1.9.3';

  static const List<String> transactionTypes = [
    'ورود',
    'برگشت',
    'تعدیل',
  ];

  static const List<String> expenseCategories = [
    'اجاره',
    'برق و آب و گاز',
    'حقوق و دستمزد',
    'حمل و نقل',
    'بسته\u200cبندی',
    'تبلیغات',
    'تعمیرات',
    'سایر',
  ];

  static const List<String> productCategories = [
    'نایلکس',
    'کیسه زباله',
    'کیسه فریزر',
    'نی و خلال',
    'قاشق و چنگال',
    'پیش دستی',
    'سفره ۴۰۰ گرمی',
    'سفره یک کیلویی',
    'دستمال',
    'لیوان ۶۰۰ گرم',
    'لیوان ۹۰۰ گرم',
    'لیوان کاغذی',
    'دستکش',
    'ظروف',
    'فوم',
    'ظروف PP',
    'ظروف PS',
    'لیوان',
    'محافظ غذا',
    'فویل',
    'بطری',
    'گالن',
    'دبه',
    'سایر',
  ];

  // SharedPreferences keys
  static const String keyRole = 'user_role';
  static const String keyManagerPin = 'manager_pin';
  static const String keyBotToken = 'telegram_bot_token';
  static const String keyChatId = 'telegram_chat_id';
  static const String keyLastBackup = 'last_backup_time';
  static const String keyAutoBackup = 'auto_backup_enabled';
}
