"""Adds the call-style ring for new requests to the generated Android project (run from shell/ after `npx cap add android`)."""
import os, re, shutil, glob
app = 'android/app'
dst = f'{app}/src/main/java/com/happyfood/ring'
os.makedirs(dst, exist_ok=True)
for f in glob.glob('native/ring/*.java'):
    shutil.copy(f, dst)

m = f'{app}/src/main/AndroidManifest.xml'
t = open(m).read()
if 'xmlns:tools' not in t:
    t = t.replace('<manifest ', '<manifest xmlns:tools="http://schemas.android.com/tools" ', 1)
if 'USE_FULL_SCREEN_INTENT' not in t:
    t = t.replace('<application', '<uses-permission android:name="android.permission.USE_FULL_SCREEN_INTENT"/>\n    <application', 1)
svc = '''
        <service android:name="com.capacitorjs.plugins.pushnotifications.MessagingService" tools:node="remove" />
        <service android:name="com.happyfood.ring.RingMessagingService" android:exported="false">
            <intent-filter><action android:name="com.google.firebase.MESSAGING_EVENT" /></intent-filter>
        </service>
        <receiver android:name="com.happyfood.ring.MuteReceiver" android:exported="false" />
'''
if 'RingMessagingService' not in t:
    t = t.replace('</application>', svc + '    </application>', 1)
# happyfood://offer?... opens the app (buttons on the ring notification)
link = '''
            <intent-filter>
                <action android:name="android.intent.action.VIEW" />
                <category android:name="android.intent.category.DEFAULT" />
                <category android:name="android.intent.category.BROWSABLE" />
                <data android:scheme="happyfood" />
            </intent-filter>'''
if 'android:scheme="happyfood"' not in t:
    t = re.sub(r'(<activity[^>]*MainActivity[^>]*>)', lambda x: x.group(1) + link, t, count=1)
open(m, 'w').write(t)

g = f'{app}/build.gradle'
b = open(g).read()
if 'firebase-messaging' not in b:
    b = b.replace('dependencies {', 'dependencies {\n    implementation "com.google.firebase:firebase-messaging:23.4.1"', 1)
open(g, 'w').write(b)
print('ring patch ok:', 'RingMessagingService' in t, 'happyfood' in t)
