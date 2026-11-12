import { EdgeTTS } from 'node-edge-tts';
const text = 'Welcome to the Rosenthal Barbershop app. Your whole shop, in your pocket: bookings, the calendar, invoices, customers and reports. Let me show you around.';
for (const [voice, file] of [['en-CA-ClaraNeural', 'clara'], ['en-CA-LiamNeural', 'liam']]) {
  const tts = new EdgeTTS({ voice, lang: 'en-CA', outputFormat: 'audio-24khz-96kbitrate-mono-mp3', timeout: 30000 });
  await tts.ttsPromise(text, `samples/${file}.mp3`);
  console.log('ok', voice);
}
