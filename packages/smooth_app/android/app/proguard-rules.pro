# google_mlkit_text_recognition references the optional Chinese/Devanagari/Japanese/Korean
# recognizers; the app only uses the Latin model, so those classes are never on the classpath.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
