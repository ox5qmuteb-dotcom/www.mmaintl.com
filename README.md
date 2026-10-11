# SRAMM Secure CI

نظام تكامل مستمر مستقل لـ **SRAMM** باستخدام GitHub Actions وrunner خاص محمي.

## الأمان

- المستودع عام، لذلك لا تضع أسرارًا أو رموز وصول فيه.
- يستخدم Pull Requests منصة `ubuntu-latest`.
- يستخدم الدفع إلى `main` runner ذاتيًا يحمل labels:
  - `self-hosted`
  - `linux`
  - `moteb-alotaibi`
- حماية الموافقات تُضبط من GitHub Environment باسم `moteb-alotaibi-secure`.

## الإعداد

1. أضف self-hosted runner موثوقًا إلى المستودع.
2. أضف labels المطلوبة أعلاه.
3. أنشئ Environment باسم `moteb-alotaibi-secure`.
4. أضف Required reviewers من حسابات GitHub الفعلية، وليس البريد الإلكتروني فقط.
5. راجع صلاحيات Actions وقيود الفروع قبل تشغيل workflow.

## الملفات

- `.github/workflows/ci.yml` — سير عمل SRAMM.
- `DEVELOPERS.md` — إرشادات المطور والصيانة.

## تنبيه مهم

الـ label `moteb-alotaibi` يحدد جهاز التشغيل ولا يثبت هوية الشخص. لا تشغّل كودًا غير موثوق على self-hosted runner؛ استخدمه فقط مع تغييرات تمت مراجعتها.

**المطور الأساسي:** moteb alotaibi  
**آخر تحديث:** 25 سبتمبر 2026
