/*
  StemOnnx - schnelle Trenn-Engine für StemMaker (htdemucs mit ONNX Runtime)

  Rechnet dasselbe Modell wie demucs.cpp (htdemucs = Demucs v4, auch
  htdemucs_ft), aber mit ONNX Runtime: auf der Grafikkarte über DirectML
  (NVIDIA, AMD, Intel) oder auf der CPU, dort etwa 4x schneller als demucs.cpp.

  Noch getrennt von StemMaker: StemMaker benutzt weiter demucs.cpp. StemOnnx
  versteht aber schon dieselben Aufrufe und schreibt dieselben Dateien, damit
  es später einfach eingebaut werden kann.

  Aufruf (die ersten vier Parameter wie bei demucs.cpp):
    StemOnnx.exe <modell> <eingang.wav> <ausgabeordner> [teile] [Optionen]

    <modell>   ggml-Modelldatei von demucs.cpp (ggml-model-htdemucs-4s-f16.bin)
               oder für htdemucs_ft der Ordner mit den 4 ft-Dateien
    [teile]    wird nur aus Gründen der Verträglichkeit angenommen und nicht
               benutzt (ONNX Runtime verteilt die Arbeit selbst auf alle Kerne)

    Optionen:
      --geraet auto|gpu|cpu   auto (Standard): Grafikkarte, wenn sie richtig
                              UND schneller rechnet als die CPU, sonst CPU
      --gpu <nummer>          bestimmte Grafikkarte (0, 1, ...), Standard: die
                              schnellste, die Windows meldet
      --kerne <anzahl>        CPU-Kerne für ONNX Runtime (Standard: alle)
      --ergebnis <datei>      Zusammenfassung (Gerät, Zeiten) an diese
                              Textdatei anhängen, für Tests
      --neu-pruefen           Grafikkarte neu prüfen, auch wenn sie früher
                              versagt hat (sonst gemerkt, siehe gpu_key)

  Ergebnis: target_0_drums.wav, target_1_bass.wav, target_2_other.wav,
  target_3_vocals.wav (32-Bit-Float, 44,1 kHz, Stereo) wie bei demucs.cpp.
  Fortschritt: Zeilen mit "( 12.3%)", für htdemucs_ft mit "DRUMS" usw. davor.

  Die Modell-Gewichte liefern wir nicht mit. Neben der exe liegt nur das
  "Gerüst" (htdemucs-geruest.onnx = Aufbau des Netzes ohne Gewichte) und die
  Liste seiner Gewichte (htdemucs-geruest.txt). Die Gewichte liest StemOnnx
  beim Start aus der ggml-Datei, die StemMaker ohnehin von der Originalquelle
  lädt, und gibt sie ONNX Runtime direkt im Speicher (AddExternalInitializers).

  Ablauf (gleich wie das Original-demucs, apply_model mit shifts=0):
    1. WAV lesen (44,1 kHz, Stereo, 16 Bit oder 32 Bit Float)
    2. normalisieren: Mittelwert und Streuung der Mono-Summe
    3. in Abschnitte von 7,8 s (343980 Samples) teilen, 25 % Überlappung
    4. je Abschnitt: STFT (hier im Programm), Modell, iSTFT (hier im Programm)
    5. Abschnitte mit Dreiecks-Gewichtung wieder zusammensetzen
    6. Normalisierung rückgängig machen, 4 WAV-Dateien schreiben

  Exit-Codes: 0 OK, 1 falscher Aufruf, 2 onnxruntime.dll fehlt/ungültig,
  3 WAV-Fehler, 4 Modell-Fehler, 5 Fehler beim Trennen, 6 Schreibfehler,
  10 Modell wird (noch) nicht unterstützt (z. B. hdemucs_mmi = v3) - dann
  soll StemMaker demucs.cpp nehmen.

  Entstanden aus dem Versuch StemGPU (Oktober 2026), siehe LIESMICH.md.
*/
#include <windows.h>
#include <stdio.h>
#include <stdarg.h>
#include <stdlib.h>
#include <string.h>
#include <wchar.h>
#include <math.h>
#include <dxgi.h>
#include "onnxruntime_c_api.h"

#define STEMONNX_VERSION "0.2"

#define SR       44100
#define SEG      343980          /* 7,8 s bei 44,1 kHz, feste Eingangslänge des Modells */
#define NSRC     4
static const char *SRC_NAMES[NSRC] = {"drums", "bass", "other", "vocals"};
static const char *SRC_UPPER[NSRC] = {"DRUMS", "BASS", "OTHER", "VOCALS"};
/* Dateinamen der 4 htdemucs_ft-Modelle (eins pro Stem, wie in StemMaker) */
static const wchar_t *FT_FILES[NSRC] = {
  L"ggml-model-htdemucs_ft_drums-4s-f16.bin", L"ggml-model-htdemucs_ft_bass-4s-f16.bin",
  L"ggml-model-htdemucs_ft_other-4s-f16.bin", L"ggml-model-htdemucs_ft_vocals-4s-f16.bin"};

static const OrtApi *g_ort = NULL;

/* Zeit in Sekunden (hochauflösend) */
static double now_s(void)
{
  LARGE_INTEGER f, c;
  QueryPerformanceFrequency(&f);
  QueryPerformanceCounter(&c);
  return (double)c.QuadPart / (double)f.QuadPart;
}

/* Text ausgeben und sofort weitergeben (StemMaker liest über eine Pipe mit) */
static void say(const char *fmt, ...)
{
  va_list ap;
  va_start(ap, fmt); vprintf(fmt, ap); va_end(ap);
  fflush(stdout);
}

/* Fehler von ONNX Runtime ausgeben. Rückgabe 1 = es gab einen Fehler. */
static char g_lasterr[1024];                 /* Text des letzten Fehlers */
static int ort_fail(OrtStatus *st, const char *was)
{
  if (st == NULL) return 0;
  snprintf(g_lasterr, sizeof g_lasterr, "%s", g_ort->GetErrorMessage(st));
  say("[ERROR] %s: %s\n", was, g_lasterr);
  g_ort->ReleaseStatus(st);
  return 1;
}

/* UTF-16 -> UTF-8 für die Ausgabe (Pfade mit Umlauten) */
static const char *u8(const wchar_t *w)
{
  static char buf[4][MAX_PATH * 4];
  static int k = 0;
  k = (k + 1) & 3;
  WideCharToMultiByte(CP_UTF8, 0, w, -1, buf[k], sizeof buf[k], NULL, NULL);
  return buf[k];
}

/* ---------- WAV lesen / schreiben ---------- */

/* Liest eine WAV-Datei in zwei Kanäle (float). Rückgabe: Anzahl Samples, 0 = Fehler. */
static long read_wav(const wchar_t *path, float **left, float **right)
{
  FILE *f = _wfopen(path, L"rb");
  if (!f) { say("[ERROR] %s nicht gefunden\n", u8(path)); return 0; }
  char id[4]; unsigned int size;
  unsigned short fmt = 0, ch = 0, bits = 0; unsigned int rate = 0;
  long n = 0;
  if (fread(id, 1, 4, f) != 4 || memcmp(id, "RIFF", 4)) goto bad;
  fseek(f, 4, SEEK_CUR);
  if (fread(id, 1, 4, f) != 4 || memcmp(id, "WAVE", 4)) goto bad;
  /* Blöcke durchgehen, bis "data" kommt */
  while (fread(id, 1, 4, f) == 4 && fread(&size, 4, 1, f) == 1) {
    if (!memcmp(id, "fmt ", 4)) {
      unsigned char b[40] = {0};
      if (fread(b, 1, size < 40 ? size : 40, f) < 16) goto bad;
      if (size > 40) fseek(f, size - 40, SEEK_CUR);
      else if (size & 1) fseek(f, 1, SEEK_CUR);
      fmt = b[0] | b[1] << 8; ch = b[2] | b[3] << 8;
      rate = b[4] | b[5] << 8 | b[6] << 16 | (unsigned)b[7] << 24;
      bits = b[14] | b[15] << 8;
      if (fmt == 0xFFFE && size >= 26) fmt = b[24] | b[25] << 8;   /* WAVE_FORMAT_EXTENSIBLE */
    } else if (!memcmp(id, "data", 4)) {
      if (ch != 2 || rate != SR || !((fmt == 1 && bits == 16) || (fmt == 3 && bits == 32))) {
        say("[ERROR] WAV muss 44100 Hz, Stereo, 16 Bit oder 32 Bit Float sein "
            "(ist: %u Hz, %u Kanäle, %u Bit, Format %u)\n", rate, ch, bits, fmt);
        fclose(f); return 0;
      }
      n = size / (bits / 8) / 2;
      *left = malloc(n * sizeof(float)); *right = malloc(n * sizeof(float));
      if (!*left || !*right) { say("[ERROR] zu wenig Arbeitsspeicher\n"); fclose(f); return 0; }
      /* blockweise lesen, sonst dauert es bei langen DJ-Mixen ewig */
      const long BLK = 65536;
      unsigned char *raw = malloc((size_t)BLK * 2 * (bits / 8));
      long i = 0;
      while (i < n) {
        long want = n - i < BLK ? n - i : BLK;
        long got = (long)fread(raw, 2 * (bits / 8), want, f);
        for (long k = 0; k < got; k++, i++) {
          if (bits == 16) {
            short *s = (short *)raw + 2 * k;
            (*left)[i] = s[0] / 32768.0f; (*right)[i] = s[1] / 32768.0f;
          } else {
            float *s = (float *)raw + 2 * k;
            (*left)[i] = s[0]; (*right)[i] = s[1];
          }
        }
        if (got < want) { n = i; break; }      /* Datei kürzer als angegeben */
      }
      free(raw);
      fclose(f);
      return n;
    } else {
      fseek(f, size + (size & 1), SEEK_CUR);
    }
  }
bad:
  say("[ERROR] %s ist keine gültige WAV-Datei\n", u8(path));
  fclose(f);
  return 0;
}

/* Schreibt Stereo als 32-Bit-Float-WAV (wie demucs.cpp). Float, damit nichts
   abgeschnitten wird: Stems können kurz über 0 dBFS gehen, StemMaker gleicht
   den Pegel danach selbst an. */
static int write_wav(const wchar_t *path, const float *l, const float *r, long n)
{
  FILE *f = _wfopen(path, L"wb");
  if (!f) { say("[ERROR] kann %s nicht schreiben\n", u8(path)); return 0; }
  unsigned int data = (unsigned int)(n * 8), riff = 4 + 26 + 12 + 8 + data;
  unsigned int rate = SR, byterate = SR * 8, fsz = 18, fact = 4, frames = (unsigned int)n;
  unsigned short fmt = 3, ch = 2, align = 8, bits = 32, cb = 0;
  fwrite("RIFF", 1, 4, f); fwrite(&riff, 4, 1, f); fwrite("WAVEfmt ", 1, 8, f);
  fwrite(&fsz, 4, 1, f); fwrite(&fmt, 2, 1, f); fwrite(&ch, 2, 1, f); fwrite(&rate, 4, 1, f);
  fwrite(&byterate, 4, 1, f); fwrite(&align, 2, 1, f); fwrite(&bits, 2, 1, f); fwrite(&cb, 2, 1, f);
  fwrite("fact", 1, 4, f); fwrite(&fact, 4, 1, f); fwrite(&frames, 4, 1, f);
  fwrite("data", 1, 4, f); fwrite(&data, 4, 1, f);
  const long BLK = 65536;
  float *buf = malloc(sizeof(float) * 2 * BLK);
  int ok = 1;
  for (long i = 0; i < n && ok; i += BLK) {
    long m = n - i < BLK ? n - i : BLK;
    for (long k = 0; k < m; k++) { buf[2 * k] = l[i + k]; buf[2 * k + 1] = r[i + k]; }
    ok = fwrite(buf, sizeof(float) * 2, m, f) == (size_t)m;
  }
  free(buf);
  if (fclose(f) != 0) ok = 0;
  if (!ok) say("[ERROR] Schreiben von %s fehlgeschlagen (Festplatte voll?)\n", u8(path));
  return ok;
}


/* ---------- Gewichte aus der ggml-Datei von demucs.cpp ----------
   Aufbau: 4 Byte Kennung 0x646d6334 ("dmc4"), dann je Tensor:
     int32 Anzahl Dimensionen, int32 Länge des Namens, int32 Dimensionen[],
     Name, Daten als float16.
   Die Namen sind dieselben wie im PyTorch-Modell (state_dict), und genau so
   heissen auch die Gewichte im Gerüst. */

typedef struct { char *name; long count; float *data; } Tensor;
typedef struct { Tensor *t; int n; } Weights;

/* float16 -> float32 (genau, inkl. kleiner Zahlen, Unendlich und NaN) */
static float half_to_float(unsigned short h)
{
  unsigned int sign = (h >> 15) & 1, e = (h >> 10) & 31, m = h & 1023, bits;
  if (e == 0) {
    if (m == 0) bits = sign << 31;
    else {                                         /* kleine Zahl: normalisieren */
      e = 127 - 15 + 1;
      while (!(m & 1024)) { m <<= 1; e--; }
      m &= 1023;
      bits = sign << 31 | e << 23 | m << 13;
    }
  } else if (e == 31) bits = sign << 31 | 255u << 23 | m << 13;
  else bits = sign << 31 | (e + 127 - 15) << 23 | m << 13;
  float x; memcpy(&x, &bits, 4);
  return x;
}

/* Rückgabe: 1 OK, 0 Fehler (Meldung schon ausgegeben) */
static int read_ggml(const wchar_t *path, Weights *w)
{
  FILE *f = _wfopen(path, L"rb");
  if (!f) { say("[ERROR] Modelldatei %s nicht gefunden\n", u8(path)); return 0; }
  int magic = 0;
  if (fread(&magic, 4, 1, f) != 1 || magic != 0x646d6334) {
    say("[ERROR] %s ist keine demucs.cpp-Modelldatei\n", u8(path)); fclose(f); return 0;
  }
  int cap = 600;
  w->t = calloc(cap, sizeof(Tensor)); w->n = 0;
  unsigned short *h = NULL; long hcap = 0;
  int hd[2];
  while (fread(hd, 4, 2, f) == 2) {
    int nd = hd[0], ln = hd[1], dims[8];
    if (nd < 0 || nd > 8 || ln <= 0 || ln > 512 || fread(dims, 4, nd, f) != (size_t)nd) goto bad;
    long cnt = 1;
    for (int i = 0; i < nd; i++) cnt *= dims[i];
    if (w->n == cap) { cap *= 2; w->t = realloc(w->t, cap * sizeof(Tensor)); }
    Tensor *t = &w->t[w->n++];
    t->name = calloc(ln + 1, 1);
    if (fread(t->name, 1, ln, f) != (size_t)ln) goto bad;
    if (cnt > hcap) { hcap = cnt; h = realloc(h, hcap * 2); }
    t->count = cnt;
    t->data = malloc(cnt * sizeof(float));
    if (!t->data || fread(h, 2, cnt, f) != (size_t)cnt) goto bad;
    for (long i = 0; i < cnt; i++) t->data[i] = half_to_float(h[i]);
  }
  free(h);
  fclose(f);
  return 1;
bad:
  say("[ERROR] Modelldatei %s ist beschädigt oder unvollständig\n", u8(path));
  free(h);
  fclose(f);
  return 0;
}

static void free_weights(Weights *w)
{
  for (int i = 0; i < w->n; i++) { free(w->t[i].name); free(w->t[i].data); }
  free(w->t); w->t = NULL; w->n = 0;
}

/* Liste der Gewichte im Gerüst (htdemucs-geruest.txt): je Zeile
   "<name> <anzahl dimensionen> <dim0> <dim1> ..." */
typedef struct { char name[128]; int nd; int64_t dims[8]; long count; } Slot;
static Slot *g_slot; static int g_nslot;

static int read_slots(const wchar_t *path)
{
  FILE *f = _wfopen(path, L"r");
  if (!f) { say("[ERROR] %s fehlt (gehört neben StemOnnx.exe)\n", u8(path)); return 0; }
  g_slot = calloc(1024, sizeof(Slot)); g_nslot = 0;
  char line[512];
  while (fgets(line, sizeof line, f) && g_nslot < 1024) {
    Slot *s = &g_slot[g_nslot];
    char *p = line;
    int used = 0;
    if (line[0] == '#' || sscanf(p, "%127s %d%n", s->name, &s->nd, &used) != 2) continue;
    if (s->nd < 0 || s->nd > 8) continue;
    p += used;
    s->count = 1;
    for (int i = 0; i < s->nd; i++) {
      long long d;
      if (sscanf(p, "%lld%n", &d, &used) != 1) { s->nd = -1; break; }
      p += used; s->dims[i] = d; s->count *= (long)d;
    }
    if (s->nd >= 0) g_nslot++;
  }
  fclose(f);
  return g_nslot > 0;
}

/* Prüft, ob die ggml-Datei genau die Gewichte des Gerüsts enthält, und
   ordnet sie in der Reihenfolge des Gerüsts an. Rückgabe 1 = passt. */
static int match_weights(Weights *w, Tensor **order)
{
  if (w->n != g_nslot) return 0;
  for (int i = 0; i < g_nslot; i++) {
    order[i] = NULL;
    for (int k = 0; k < w->n; k++)
      if (!strcmp(w->t[k].name, g_slot[i].name)) { order[i] = &w->t[k]; break; }
    if (!order[i] || order[i]->count != g_slot[i].count) return 0;
  }
  return 1;
}


/* ---------- STFT / iSTFT (wie HTDemucs._spec / _ispec) ----------
   Das Programm rechnet die STFT selbst mit einer FFT, das Modell bekommt das
   fertige Spektrum. Im Modell (als riesige Faltung) brauchte sie auf der
   Grafikkarte zu viel Speicher.
     n_fft 4096, Hop 1024, Hann-Fenster, normiert (1/sqrt(4096)),
     center=True mit Spiegel-Rand, 2048 Frequenzen, 336 Zeitfenster. */
#define NFFT   4096
#define HOP    1024
#define NBIN   2048
#define LE     336                         /* ceil(SEG / HOP) */
#define PADS   (HOP / 2 * 3)               /* 1536: Rand wie in _spec */
#define NFR    (LE + 4)                    /* 340 Fenster inkl. Rand */
#define P1LEN  (SEG + PADS + PADS + LE * HOP - SEG)        /* 347136 */
#define ACCLEN (NFFT + HOP * (NFR - 1))

static double g_win[NFFT];                 /* periodisches Hann-Fenster */
static double g_cos[NFFT / 2], g_sin[NFFT / 2];
static float *g_env;                       /* Summe der Fenster² für die iSTFT */

/* Spiegeln ohne Randwiederholung (wie numpy/torch "reflect") */
static long reflect(long i, long len)
{
  while (i < 0 || i >= len) {
    if (i < 0) i = -i;
    if (i >= len) i = 2 * (len - 1) - i;
  }
  return i;
}

/* komplexe FFT (Radix 2, in-place), inv=1 rückwärts (ohne 1/N) */
static void fft(double *re, double *im, int inv)
{
  for (int i = 1, j = 0; i < NFFT; i++) {          /* Bit-Umkehr */
    int bit = NFFT >> 1;
    for (; j & bit; bit >>= 1) j ^= bit;
    j ^= bit;
    if (i < j) { double t = re[i]; re[i] = re[j]; re[j] = t; t = im[i]; im[i] = im[j]; im[j] = t; }
  }
  for (int len = 2; len <= NFFT; len <<= 1) {
    int step = NFFT / len;
    for (int i = 0; i < NFFT; i += len)
      for (int k = 0; k < len / 2; k++) {
        double wr = g_cos[k * step], wi = inv ? g_sin[k * step] : -g_sin[k * step];
        double *ar = re + i + k, *ai = im + i + k, *br = re + i + k + len / 2, *bi = im + i + k + len / 2;
        double tr = *br * wr - *bi * wi, ti = *br * wi + *bi * wr;
        *br = *ar - tr; *bi = *ai - ti; *ar += tr; *ai += ti;
      }
  }
}

static void stft_init(void)
{
  for (int i = 0; i < NFFT; i++) g_win[i] = 0.5 - 0.5 * cos(2 * M_PI * i / NFFT);
  for (int i = 0; i < NFFT / 2; i++) { g_cos[i] = cos(2 * M_PI * i / NFFT); g_sin[i] = sin(2 * M_PI * i / NFFT); }
  g_env = calloc(ACCLEN, sizeof(float));
  for (int f = 0; f < NFR; f++)
    for (int i = 0; i < NFFT; i++) g_env[f * HOP + i] += (float)(g_win[i] * g_win[i]);
}

/* ein Kanal (SEG Samples) -> Spektrum (Real- und Imaginärteil je NBIN x LE) */
static void stft_channel(const float *x, float *spec_re, float *spec_im)
{
  double *re = malloc(sizeof(double) * NFFT * 2), *im = re + NFFT;
  const double norm = 1.0 / sqrt((double)NFFT);
  for (int f = 2; f < 2 + LE; f++) {               /* Fenster 2..337 werden gebraucht */
    for (int i = 0; i < NFFT; i++) {
      long p2 = (long)f * HOP + i;                 /* Position im doppelt gepolsterten Signal */
      long p1 = reflect(p2 - NFFT / 2, P1LEN);     /* center=True */
      long p0 = reflect(p1 - PADS, SEG);           /* Rand aus _spec */
      re[i] = x[p0] * g_win[i]; im[i] = 0;
    }
    fft(re, im, 0);
    for (int k = 0; k < NBIN; k++) {
      spec_re[(size_t)k * LE + (f - 2)] = (float)(re[k] * norm);
      spec_im[(size_t)k * LE + (f - 2)] = (float)(im[k] * norm);
    }
  }
  free(re);
}

/* Spektrum (NBIN x LE, Real + Imag) -> Zeitsignal, wird zu out (SEG) ADDIERT */
static void istft_channel(const float *spec_re, const float *spec_im, float *out)
{
  double *re = malloc(sizeof(double) * (NFFT * 2 + ACCLEN)), *im = re + NFFT, *acc = im + NFFT;
  const double scale = sqrt((double)NFFT) / NFFT;  /* normiert, dazu 1/N der inversen FFT */
  memset(acc, 0, sizeof(double) * ACCLEN);
  for (int f = 2; f < 2 + LE; f++) {               /* Fenster 0,1 und 338,339 sind Null */
    for (int k = 0; k < NFFT; k++) { re[k] = 0; im[k] = 0; }
    for (int k = 0; k < NBIN; k++) {
      re[k] = spec_re[(size_t)k * LE + (f - 2)];
      im[k] = spec_im[(size_t)k * LE + (f - 2)];
    }
    im[0] = 0;                                     /* wie irfft: Imaginärteil von DC zählt nicht */
    for (int k = 1; k < NBIN; k++) { re[NFFT - k] = re[k]; im[NFFT - k] = -im[k]; }
    fft(re, im, 1);
    for (int i = 0; i < NFFT; i++) acc[(size_t)f * HOP + i] += re[i] * scale * g_win[i];
  }
  for (long j = 0; j < SEG; j++) {
    long idx = NFFT / 2 + PADS + j;
    double e = g_env[idx]; if (e < 1e-11) e = 1e-11;
    out[j] += (float)(acc[idx] / e);
  }
  free(re);
}

/* STFT der 2 Kanäle und iSTFT der 8 Spuren (4 Stems x 2 Kanäle) laufen
   gleichzeitig in eigenen Threads. Auf der Grafikkarte wäre das sonst ein
   grosser Teil der Rechenzeit. */
typedef struct { int inverse; const float *x; float *re, *im, *out; } FftJob;

static DWORD WINAPI fft_thread(LPVOID p)
{
  FftJob *j = p;
  if (j->inverse) istft_channel(j->re, j->im, j->out);
  else stft_channel(j->x, j->re, j->im);
  return 0;
}

static void run_jobs(FftJob *jobs, int n)
{
  HANDLE h[16];
  for (int i = 0; i < n; i++) {
    h[i] = CreateThread(NULL, 0, fft_thread, &jobs[i], 0, NULL);
    if (!h[i]) fft_thread(&jobs[i]);                /* ohne Thread: direkt rechnen */
  }
  for (int i = 0; i < n; i++)
    if (h[i]) { WaitForSingleObject(h[i], INFINITE); CloseHandle(h[i]); }
}

/* Einen Abschnitt trennen: in (2 x SEG) -> res (4 x 2 x SEG) */
static float *g_spec;
static OrtStatus *run_segment(OrtSession *sess, OrtMemoryInfo *mem, float *in, float *res, double *t_model)
{
  static const char *in_names[] = {"mix", "spec"}, *out_names[] = {"wave", "spec_out"};
  int64_t shape_mix[3] = {1, 2, SEG}, shape_spec[5] = {1, 2, 2, NBIN, LE};
  size_t plane = (size_t)NBIN * LE;
  FftJob jobs[8];
  for (int c = 0; c < 2; c++) {                    /* Form spec: 1 x Kanal x (Re,Im) x 2048 x 336 */
    jobs[c].inverse = 0; jobs[c].x = in + (size_t)c * SEG;
    jobs[c].re = g_spec + (c * 2 + 0) * plane; jobs[c].im = g_spec + (c * 2 + 1) * plane;
  }
  run_jobs(jobs, 2);
  OrtValue *x[2] = {NULL, NULL}, *y[2] = {NULL, NULL};
  OrtStatus *st = g_ort->CreateTensorWithDataAsOrtValue(mem, in, sizeof(float) * 2 * SEG, shape_mix, 3,
                                                        ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT, &x[0]);
  if (!st) st = g_ort->CreateTensorWithDataAsOrtValue(mem, g_spec, sizeof(float) * 4 * plane, shape_spec, 5,
                                                      ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT, &x[1]);
  double t = now_s();
  if (!st) st = g_ort->Run(sess, NULL, in_names, (const OrtValue *const *)x, 2, out_names, 2, y);
  if (t_model) *t_model = now_s() - t;
  if (x[0]) g_ort->ReleaseValue(x[0]);
  if (x[1]) g_ort->ReleaseValue(x[1]);
  if (st) return st;
  float *wave, *zo;
  g_ort->GetTensorMutableData(y[0], (void **)&wave);   /* 1 x 4 x 2 x SEG (Zeitzweig) */
  g_ort->GetTensorMutableData(y[1], (void **)&zo);     /* 1 x 4 x 2 x (Re,Im) x 2048 x 336 */
  memcpy(res, wave, sizeof(float) * NSRC * 2 * SEG);
  for (int s = 0; s < NSRC; s++)
    for (int c = 0; c < 2; c++) {
      FftJob *j = &jobs[s * 2 + c];
      const float *zr = zo + ((size_t)(s * 2 + c) * 2 + 0) * plane;
      j->inverse = 1; j->re = (float *)zr; j->im = (float *)zr + plane;
      j->out = res + ((size_t)s * 2 + c) * SEG;
    }
  run_jobs(jobs, 8);
  g_ort->ReleaseValue(y[0]); g_ort->ReleaseValue(y[1]);
  return NULL;
}


/* ---------- Sitzungen (ONNX Runtime) ---------- */

static OrtEnv *g_env_ort;
static OrtMemoryInfo *g_mem;
static wchar_t g_skeleton[MAX_PATH * 2];
static int g_kerne = 0;
static OrtValue **g_wvals;                         /* Gewichte als OrtValue, Reihenfolge = Gerüst */
static const char **g_wnames;

/* Gewichte eines Modells für ONNX Runtime bereitstellen (ohne Kopie) */
static int prepare_weights(Tensor **order)
{
  for (int i = 0; i < g_nslot; i++) {
    if (g_wvals[i]) g_ort->ReleaseValue(g_wvals[i]);
    g_wvals[i] = NULL;
    g_wnames[i] = g_slot[i].name;
    if (ort_fail(g_ort->CreateTensorWithDataAsOrtValue(g_mem, order[i]->data, sizeof(float) * order[i]->count,
                                                       g_slot[i].dims, g_slot[i].nd,
                                                       ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT, &g_wvals[i]),
                 "Gewichte vorbereiten"))
      return 0;
  }
  return 1;
}

/* Arten, wie gerechnet wird. DirectML MIT Graph-Fusion rechnet htdemucs
   falsch (Diagnose auf der RTX 4060 Ti, 12.10.2026: Werte bis 680000 statt
   höchstens ca. 3) und wird darum nie benutzt. */
enum { DEV_CPU = 0, DEV_DML = 1, DEV_DML_NOMETA = 2 };
static const char *DEV_NAMES[] = {"CPU", "Grafikkarte (DirectML)", "Grafikkarte (DirectML, ohne Metacommands)"};

/* Sitzung erzeugen. gpu_id < 0: schnellste Grafikkarte nehmen. */
static OrtSession *new_session(int dev, int gpu_id)
{
  OrtSessionOptions *opt;
  OrtSession *s = NULL;
  if (ort_fail(g_ort->CreateSessionOptions(&opt), "Sitzung vorbereiten")) return NULL;
  g_ort->SetSessionGraphOptimizationLevel(opt, ORT_ENABLE_ALL);
  if (g_kerne > 0) g_ort->SetIntraOpNumThreads(opt, g_kerne);
  if (ort_fail(g_ort->AddExternalInitializers(opt, g_wnames, (const OrtValue *const *)g_wvals, g_nslot),
               "Gewichte übergeben")) {
    g_ort->ReleaseSessionOptions(opt);
    return NULL;
  }
  if (dev != DEV_CPU) {
    /* DirectML verlangt: kein Speicher-Muster, nacheinander rechnen */
    g_ort->DisableMemPattern(opt);
    g_ort->SetSessionExecutionMode(opt, ORT_SEQUENTIAL);
    g_ort->AddSessionConfigEntry(opt, "ep.dml.disable_graph_fusion", "1");
    char id[16]; snprintf(id, sizeof id, "%d", gpu_id < 0 ? 0 : gpu_id);
    const char *meta = dev == DEV_DML_NOMETA ? "True" : "False";
    OrtStatus *st;
    if (gpu_id < 0) {
      /* ohne Nummer: die stärkste Grafikkarte (bei Laptops sonst oft die
         schwache im Prozessor) */
      const char *k[] = {"performance_preference", "device_filter", "disable_metacommands"};
      const char *v[] = {"high_performance", "gpu", meta};
      st = g_ort->SessionOptionsAppendExecutionProvider(opt, "DML", k, v, 3);
      if (st) {                                    /* ältere DirectML-Version: nur Nummer 0 */
        g_ort->ReleaseStatus(st);
        const char *k2[] = {"device_id", "disable_metacommands"}, *v2[] = {id, meta};
        st = g_ort->SessionOptionsAppendExecutionProvider(opt, "DML", k2, v2, 2);
      }
    } else {
      const char *k[] = {"device_id", "disable_metacommands"}, *v[] = {id, meta};
      st = g_ort->SessionOptionsAppendExecutionProvider(opt, "DML", k, v, 2);
    }
    if (ort_fail(st, "Grafikkarte einschalten")) {
      g_ort->ReleaseSessionOptions(opt);
      return NULL;
    }
  }
  if (ort_fail(g_ort->CreateSession(g_env_ort, g_skeleton, opt, &s), "Modell laden")) s = NULL;
  g_ort->ReleaseSessionOptions(opt);
  return s;
}

/* Prüft das Ergebnis eines Abschnitts: die Eingabe ist normalisiert, gute
   Stems bleiben deutlich unter 100. Fängt auch NaN ab. */
static int plausible(const float *res, float *mx)
{
  *mx = 0;
  for (size_t k = 0; k < (size_t)NSRC * 2 * SEG; k++) {
    float a = fabsf(res[k]);
    if (!(a < 100.0f)) { *mx = a; return 0; }
    if (a > *mx) *mx = a;
  }
  return 1;
}

/* Abstand zwischen zwei Ergebnissen in dB (Signal / Abweichung) */
static double snr_db(const float *ref, const float *x)
{
  double s = 0, d = 0;
  for (size_t k = 0; k < (size_t)NSRC * 2 * SEG; k++) {
    double e = (double)ref[k] - x[k];
    s += (double)ref[k] * ref[k]; d += e * e;
  }
  if (d <= 0) return 200;
  return 10 * log10(s / d);
}


/* ---------- Grafikkarte erkennen und Ergebnis merken ----------
   Die Prüfung der Grafikkarte kostet beim ersten Mal Zeit (auf dem
   Werkstatt-PC mit GT 1030: 27 s, bis die Karte zweimal ausgestiegen war).
   Das Ergebnis kommt darum in %LOCALAPPDATA%\StemOnnx\geraet.txt, zusammen
   mit Name und Treiber-Version der Grafikkarten. Beim nächsten Start wird
   eine Karte, die schon einmal versagt hat, gleich übersprungen. Nach einem
   Treiber-Update oder einer neuen Karte ändert sich der Schlüssel, dann wird
   wieder geprüft. Mit --neu-pruefen auch sonst. */

/* IIDs selbst angeben, dann braucht der Build keine Zusatz-Bibliothek */
static const GUID MY_IID_IDXGIFactory1 = {0x770aae78, 0xf26f, 0x4dba, {0xa8, 0x29, 0x25, 0x3c, 0x83, 0xd1, 0xb3, 0x87}};
static const GUID MY_IID_IDXGIDevice = {0x54ec77fa, 0x1377, 0x44e6, {0x8c, 0x32, 0x88, 0xfd, 0x5f, 0x44, 0xc8, 0x4c}};

/* Schlüssel aus allen echten Grafikkarten: "Name|Treiber;Name|Treiber".
   Leer = keine Grafikkarte (nur Software-Anzeige, z. B. in einer VM). */
static void gpu_key(char *key, size_t size)
{
  key[0] = 0;
  HMODULE d = LoadLibraryA("dxgi.dll");
  if (!d) return;
  typedef HRESULT (WINAPI *CreateFn)(REFIID, void **);
  CreateFn create = (CreateFn)GetProcAddress(d, "CreateDXGIFactory1");
  IDXGIFactory1 *f = NULL;
  if (!create || FAILED(create(&MY_IID_IDXGIFactory1, (void **)&f)) || !f) return;
  IDXGIAdapter1 *a;
  for (UINT i = 0; f->lpVtbl->EnumAdapters1(f, i, &a) == S_OK; i++) {
    DXGI_ADAPTER_DESC1 dd;
    LARGE_INTEGER umd = {0};
    if (SUCCEEDED(a->lpVtbl->GetDesc1(a, &dd)) && !(dd.Flags & DXGI_ADAPTER_FLAG_SOFTWARE)
        && dd.VendorId != 0x1414) {                  /* 0x1414 = Microsoft (Basic Render Driver) */
      a->lpVtbl->CheckInterfaceSupport(a, &MY_IID_IDXGIDevice, &umd);
      char name[128];
      WideCharToMultiByte(CP_UTF8, 0, dd.Description, -1, name, sizeof name, NULL, NULL);
      size_t L = strlen(key);
      snprintf(key + L, size - L, "%s%s|%u.%u.%u.%u", L ? ";" : "", name,
               (unsigned)HIWORD(umd.HighPart), (unsigned)LOWORD(umd.HighPart),
               (unsigned)HIWORD(umd.LowPart), (unsigned)LOWORD(umd.LowPart));
    }
    a->lpVtbl->Release(a);
  }
  f->lpVtbl->Release(f);
}

static wchar_t *cache_path(void)
{
  static wchar_t p[MAX_PATH * 2];
  wchar_t base[MAX_PATH * 2];
  DWORD n = GetEnvironmentVariableW(L"LOCALAPPDATA", base, MAX_PATH * 2);
  if (n == 0 || n >= MAX_PATH * 2) return NULL;
  swprintf(p, MAX_PATH * 2, L"%ls\\StemOnnx", base);
  CreateDirectoryW(p, NULL);
  swprintf(p, MAX_PATH * 2, L"%ls\\StemOnnx\\geraet.txt", base);
  return p;
}

/* Gemerktes Ergebnis für diesen Schlüssel lesen ("ein" oder "aus: Grund").
   Rückgabe 0 = nichts gemerkt. */
static int cache_read(const char *key, char *status, size_t size)
{
  wchar_t *p = cache_path();
  FILE *f = p ? _wfopen(p, L"r") : NULL;
  if (!f) return 0;
  char line[1024];
  int found = 0;
  while (!found && fgets(line, sizeof line, f)) {
    line[strcspn(line, "\r\n")] = 0;
    char *tab = strchr(line, '\t');
    if (tab && (size_t)(tab - line) == strlen(key) && !strncmp(line, key, tab - line)) {
      snprintf(status, size, "%s", tab + 1);
      found = 1;
    }
  }
  fclose(f);
  return found;
}

static void cache_write(const char *key, const char *status)
{
  wchar_t *p = cache_path();
  FILE *f = p ? _wfopen(p, L"w") : NULL;
  if (!f) return;
  fprintf(f, "%s\t%s\n", key, status);
  fclose(f);
}

/* Windows-Fehler "Grafikkarte hängt / wurde entfernt / zurückgesetzt": dann
   hilft auch die zweite DirectML-Variante nicht mehr */
static int device_lost(void)
{
  return strstr(g_lasterr, "887A0005") || strstr(g_lasterr, "887A0006") || strstr(g_lasterr, "887A0007")
      || strstr(g_lasterr, "887a0005") || strstr(g_lasterr, "887a0006") || strstr(g_lasterr, "887a0007");
}


/* ---------- Hauptprogramm ---------- */

/* Abschnitt Nummer i in den Eingangspuffer kopieren. Das kurze Endstück wird
   mittig mit echtem Audio davor aufgefüllt (wie demucs, TensorChunk.padded). */
static long g_n, g_stride;
static float *g_inL, *g_inR;
static void fill_segment(long off, float *in, long *st_out, long *len_out)
{
  long len = g_n - off < SEG ? g_n - off : SEG;
  long st = off - (SEG - len) / 2;
  memset(in, 0, sizeof(float) * 2 * SEG);
  for (long k = 0; k < SEG; k++) {
    long i = st + k;
    if (i < 0 || i >= g_n) continue;
    in[k] = g_inL[i]; in[SEG + k] = g_inR[i];
  }
  *st_out = st; *len_out = len;
}

int wmain(int argc, wchar_t **argv)
{
  SetConsoleOutputCP(CP_UTF8);   /* Umlaute richtig anzeigen */
  say("StemOnnx %s - htdemucs mit ONNX Runtime (Grafikkarte oder CPU)\n", STEMONNX_VERSION);

  /* --- Parameter --- */
  const wchar_t *pos[4] = {NULL, NULL, NULL, NULL};
  int npos = 0, gpu_id = -1;
  const char *geraet = "auto";
  const wchar_t *ergebnis = NULL;
  int neu_pruefen = 0;
  for (int i = 1; i < argc; i++) {
    if (!wcscmp(argv[i], L"--geraet") && i + 1 < argc) {
      i++;
      if (!_wcsicmp(argv[i], L"gpu")) geraet = "gpu";
      else if (!_wcsicmp(argv[i], L"cpu")) geraet = "cpu";
      else geraet = "auto";
    } else if (!wcscmp(argv[i], L"--gpu") && i + 1 < argc) gpu_id = _wtoi(argv[++i]);
    else if (!wcscmp(argv[i], L"--kerne") && i + 1 < argc) g_kerne = _wtoi(argv[++i]);
    else if (!wcscmp(argv[i], L"--ergebnis") && i + 1 < argc) ergebnis = argv[++i];
    else if (!wcscmp(argv[i], L"--neu-pruefen")) neu_pruefen = 1;
    else if (npos < 4) pos[npos++] = argv[i];
  }
  if (npos < 3) {
    say("\nAufruf: StemOnnx.exe <modell> <eingang.wav> <ausgabeordner> [teile]\n"
        "        [--geraet auto|gpu|cpu] [--gpu <nummer>] [--kerne <anzahl>] [--ergebnis <datei>] [--neu-pruefen]\n\n"
        "<modell>: ggml-model-htdemucs-4s-f16.bin oder der Ordner mit den 4 htdemucs_ft-Dateien\n");
    return 1;
  }
  const wchar_t *model_arg = pos[0], *wav_path = pos[1], *out_dir = pos[2];

  /* --- onnxruntime.dll aus dem Programmordner laden (nicht irgendeine im
         Suchpfad) --- */
  wchar_t exe_dir[MAX_PATH * 2], p[MAX_PATH * 2];
  GetModuleFileNameW(NULL, exe_dir, MAX_PATH * 2);
  wchar_t *slash = wcsrchr(exe_dir, L'\\');
  if (slash) slash[1] = 0; else exe_dir[0] = 0;
  SetDllDirectoryW(exe_dir);                        /* DirectML.dll ebenfalls von hier */
  swprintf(p, MAX_PATH * 2, L"%lsonnxruntime.dll", exe_dir);
  HMODULE dll = LoadLibraryW(p);
  if (!dll) { say("[ERROR] onnxruntime.dll fehlt (muss neben StemOnnx.exe liegen)\n"); return 2; }
  typedef const OrtApiBase *(ORT_API_CALL *GetApiBaseFn)(void);
  GetApiBaseFn get_base = (GetApiBaseFn)GetProcAddress(dll, "OrtGetApiBase");
  if (!get_base) { say("[ERROR] onnxruntime.dll ist ungültig\n"); return 2; }
  g_ort = get_base()->GetApi(ORT_API_VERSION);
  if (!g_ort) { say("[ERROR] onnxruntime.dll ist zu alt\n"); return 2; }

  /* --- Gerüst und Gewichts-Liste --- */
  swprintf(g_skeleton, MAX_PATH * 2, L"%lshtdemucs-geruest.onnx", exe_dir);
  swprintf(p, MAX_PATH * 2, L"%lshtdemucs-geruest.txt", exe_dir);
  if (GetFileAttributesW(g_skeleton) == INVALID_FILE_ATTRIBUTES) {
    say("[ERROR] %s fehlt (gehört neben StemOnnx.exe)\n", u8(g_skeleton));
    return 4;
  }
  if (!read_slots(p)) return 4;

  /* --- Modell(e): eine Datei = htdemucs, ein Ordner = htdemucs_ft --- */
  wchar_t model_files[NSRC][MAX_PATH * 2];
  int nmodels = 1;
  DWORD attr = GetFileAttributesW(model_arg);
  if (attr != INVALID_FILE_ATTRIBUTES && (attr & FILE_ATTRIBUTE_DIRECTORY)) {
    nmodels = NSRC;
    for (int s = 0; s < NSRC; s++) {
      size_t L = wcslen(model_arg);
      int sep = L > 0 && (model_arg[L - 1] == L'\\' || model_arg[L - 1] == L'/');
      swprintf(model_files[s], MAX_PATH * 2, L"%ls%ls%ls", model_arg, sep ? L"" : L"\\", FT_FILES[s]);
    }
  } else {
    wcsncpy(model_files[0], model_arg, MAX_PATH * 2 - 1);
    model_files[0][MAX_PATH * 2 - 1] = 0;
    /* hdemucs_mmi (Demucs v3) hat einen anderen Aufbau: noch nicht unterstützt */
    if (wcsstr(model_files[0], L"hdemucs_mmi") && !wcsstr(model_files[0], L"htdemucs")) {
      say("[ERROR] Modell wird von StemOnnx nicht unterstützt (nur htdemucs und htdemucs_ft): %s\n",
          u8(model_files[0]));
      return 10;
    }
  }

  /* --- Audio lesen und normalisieren --- */
  long n = read_wav(wav_path, &g_inL, &g_inR);
  if (n <= 0) return 3;
  g_n = n;
  double sum = 0, sum2 = 0;
  for (long i = 0; i < n; i++) { double m = 0.5 * (g_inL[i] + g_inR[i]); sum += m; sum2 += m * m; }
  float mean = (float)(sum / n);
  double var = n > 1 ? (sum2 - sum * sum / n) / (n - 1) : 0;    /* wie torch.std (n-1) */
  float std = (float)sqrt(var > 0 ? var : 0);
  if (std < 1e-8f) std = 1e-8f;
  for (long i = 0; i < n; i++) { g_inL[i] = (g_inL[i] - mean) / std; g_inR[i] = (g_inR[i] - mean) / std; }
  say("Audio: %.1f s\n", n / (double)SR);

  /* --- ONNX Runtime vorbereiten --- */
  double t0 = now_s();
  if (ort_fail(g_ort->CreateEnv(ORT_LOGGING_LEVEL_ERROR, "StemOnnx", &g_env_ort), "ONNX Runtime starten")) return 4;
  if (ort_fail(g_ort->CreateCpuMemoryInfo(OrtArenaAllocator, OrtMemTypeDefault, &g_mem), "Speicher")) return 4;
  stft_init();
  g_spec = malloc(sizeof(float) * 4 * NBIN * LE);
  g_wvals = calloc(g_nslot, sizeof(OrtValue *));
  g_wnames = calloc(g_nslot, sizeof(char *));
  Tensor **order = calloc(g_nslot, sizeof(Tensor *));

  /* Ergebnis-Puffer: alle 4 Stems über den ganzen Song + Gewichts-Summe */
  float *out = calloc((size_t)NSRC * 2 * n, sizeof(float));
  float *wsum = calloc(n, sizeof(float));
  float *w = malloc(sizeof(float) * SEG);
  float *in = malloc(sizeof(float) * 2 * SEG);
  float *res = malloc(sizeof(float) * NSRC * 2 * SEG);
  float *res_cpu = malloc(sizeof(float) * NSRC * 2 * SEG);
  if (!out || !wsum || !w || !in || !res || !res_cpu || !g_spec) {
    say("[ERROR] zu wenig Arbeitsspeicher für %.0f Minuten Audio\n", n / (double)SR / 60);
    return 5;
  }
  /* Dreiecks-Gewichtung wie demucs: 1..SEG/2 und zurück, auf 1 normiert */
  for (int k = 0; k < SEG / 2; k++) w[k] = (float)(k + 1);
  for (int k = SEG / 2; k < SEG; k++) w[k] = (float)(SEG - k);
  for (int k = 0; k < SEG; k++) w[k] /= (float)(SEG / 2);
  g_stride = (long)(0.75 * SEG);
  int chunks = (int)((n + g_stride - 1) / g_stride);
  /* Probe-Abschnitt für die Wahl des Geräts: der bei ca. 30 s (dort ist meist
     volle Musik), bei kurzen Songs der mittlere. Sein Ergebnis wird benutzt,
     nicht weggeworfen. */
  int probe = (int)(30L * SR / g_stride);
  if (probe >= chunks) probe = chunks / 2;

  int dev = DEV_CPU;
  char dev_txt[160] = "CPU";

  /* auto: Grafikkarte nur probieren, wenn es eine gibt und sie nicht schon
     einmal versagt hat */
  char key[512], merk[256] = "aus: unbekannt";
  int try_gpu = strcmp(geraet, "cpu") != 0;
  gpu_key(key, sizeof key);
  if (!strcmp(geraet, "auto")) {
    say("Grafikkarte: %s\n", key[0] ? key : "keine gefunden");
    if (!key[0]) try_gpu = 0;
    else if (!neu_pruefen && cache_read(key, merk, sizeof merk) && strncmp(merk, "aus", 3) == 0) {
      say("Grafikkarte übersprungen, frühere Prüfung: %s (neu prüfen mit --neu-pruefen)\n", merk);
      try_gpu = 0;
    }
  }
  double t_load = 0, t_sep = 0;

  for (int mi = 0; mi < nmodels; mi++) {
    /* Gewichte dieses Modells laden */
    double tl = now_s();
    Weights wt = {0};
    if (!read_ggml(model_files[mi], &wt)) return 4;
    if (!match_weights(&wt, order)) {
      say("[ERROR] Modell wird von StemOnnx nicht unterstützt (passt nicht zum htdemucs-Gerüst): %s\n",
          u8(model_files[mi]));
      return 10;
    }
    if (!prepare_weights(order)) return 4;

    OrtSession *sess = NULL;
    int done_probe = 0;
    const char *prefix = nmodels > 1 ? SRC_UPPER[mi] : "";
    const char *tab = nmodels > 1 ? "\t " : "";

    if (mi == 0 && try_gpu) {
      /* Grafikkarte probieren: jede Variante muss den Probe-Abschnitt richtig
         rechnen. Bei "auto" auch schneller als die CPU sein, und das Ergebnis
         muss mit der CPU übereinstimmen (gemessen: 56 bis 66 dB Abstand,
         also nur Rundung). */
      long pst, plen;
      fill_segment((long)probe * g_stride, in, &pst, &plen);
      double t_cpu = 0;
      OrtSession *cpu = NULL;
      if (!strcmp(geraet, "auto")) {
        cpu = new_session(DEV_CPU, -1);
        if (!cpu) return 4;
        if (ort_fail(run_segment(cpu, g_mem, in, res_cpu, &t_cpu), "Probe auf der CPU")) return 5;
        say("Probe CPU: %.2f s\n", t_cpu);
      }
      for (int d = DEV_DML; d <= DEV_DML_NOMETA && !sess; d++) {
        say("Probiere %s ...\n", DEV_NAMES[d]);
        OrtSession *g = new_session(d, gpu_id);
        if (!g) { snprintf(merk, sizeof merk, "aus: lässt sich nicht einschalten"); continue; }
        double t1 = 0, t2 = 0;
        float mx;
        /* zweimal: der erste Lauf richtet die Grafikkarte erst ein */
        int ok = !ort_fail(run_segment(g, g_mem, in, res, &t1), "Probe auf der Grafikkarte");
        if (ok) ok = !ort_fail(run_segment(g, g_mem, in, res, &t2), "Probe auf der Grafikkarte");
        if (!ok) snprintf(merk, sizeof merk, "aus: Probe abgestürzt");
        if (ok && !plausible(res, &mx)) {
          say("Probe rechnet falsch (Wert %g)\n", mx);
          snprintf(merk, sizeof merk, "aus: rechnet falsch");
          ok = 0;
        }
        if (ok && cpu) {
          double snr = snr_db(res_cpu, res);
          say("Probe Grafikkarte: %.2f s, Abstand zur CPU %.0f dB\n", t2, snr);
          if (snr < 40) {
            say("-> Grafikkarte rechnet ungenau, nicht benutzt\n");
            snprintf(merk, sizeof merk, "aus: rechnet ungenau (%.0f dB)", snr);
            ok = 0;
          } else if (t2 * 1.2 > t_cpu) {
            say("-> Grafikkarte nicht schneller als die CPU, rechne auf der CPU\n");
            snprintf(merk, sizeof merk, "aus: nicht schneller als die CPU (%.2f s gegen %.2f s)", t2, t_cpu);
            g_ort->ReleaseSession(g);
            break;
          }
        }
        if (ok) { sess = g; dev = d; }
        else {
          g_ort->ReleaseSession(g);
          if (device_lost()) {
            say("-> Grafikkarte wurde von Windows zurückgesetzt, keine weitere Variante\n");
            break;
          }
        }
      }
      /* Ergebnis merken (nur bei auto, dort wurde richtig verglichen) */
      if (!strcmp(geraet, "auto") && key[0]) cache_write(key, sess ? "ein" : merk);
      if (sess) {
        if (cpu) g_ort->ReleaseSession(cpu);
        cpu = NULL;
      } else if (cpu) {
        sess = cpu; dev = DEV_CPU;
        memcpy(res, res_cpu, sizeof(float) * NSRC * 2 * SEG);
      }
      if (sess) {
        /* Ergebnis des Probe-Abschnitts übernehmen (bei auto das der CPU,
           wenn die CPU gewählt wurde, sonst das der Grafikkarte) */
        long skip = (long)probe * g_stride - pst;
        for (int s = 0; s < NSRC; s++)
          for (int c = 0; c < 2; c++) {
            if (nmodels > 1 && s != mi) continue;   /* htdemucs_ft: nur der eigene Stem */
            const float *src = res + ((size_t)s * 2 + c) * SEG + skip;
            float *dst = out + ((size_t)s * 2 + c) * n + (long)probe * g_stride;
            for (long k = 0; k < plen; k++) dst[k] += w[k] * src[k];
          }
        for (long k = 0; k < plen; k++) wsum[(long)probe * g_stride + k] += w[k];
        done_probe = 1;
      }
      snprintf(dev_txt, sizeof dev_txt, "%s", DEV_NAMES[dev]);
    }
    if (!sess) {
      sess = new_session(dev, gpu_id);
      if (!sess && dev != DEV_CPU) {                 /* Grafikkarte geht beim 2. Modell nicht */
        dev = DEV_CPU;
        snprintf(dev_txt + strlen(dev_txt), sizeof dev_txt - strlen(dev_txt), ", ab %s CPU", SRC_UPPER[mi]);
        sess = new_session(DEV_CPU, -1);
      }
      if (!sess) return 4;
    }
    t_load += now_s() - tl;
    if (mi == 0) say("Rechnet auf: %s\n", dev_txt);

    /* --- Abschnitte trennen und zusammensetzen --- */
    double ts = now_s();
    int nr = done_probe;
    for (int ci = 0; ci < chunks; ci++) {
      if (done_probe && ci == probe) continue;
      long off = (long)ci * g_stride, st, len;
      fill_segment(off, in, &st, &len);
      OrtStatus *rs = run_segment(sess, g_mem, in, res, NULL);
      float mx;
      if (!rs && dev != DEV_CPU && !plausible(res, &mx)) {
        say("[ERROR] Grafikkarte rechnet falsch (Wert %g)\n", mx);
        rs = g_ort->CreateStatus(ORT_FAIL, "unplausibles Ergebnis");
      }
      if (rs && dev != DEV_CPU) {
        /* Grafikkarte fällt mitten im Song aus (z. B. setzt Windows eine
           schwache Karte nach 2 s Rechenzeit zurück): auf der CPU weiter */
        ort_fail(rs, "Trennen auf der Grafikkarte");
        say("-> Grafikkarte ausgefallen, rechne ab hier auf der CPU weiter\n");
        if (key[0]) cache_write(key, "aus: mitten im Song ausgefallen");
        g_ort->ReleaseSession(sess);
        dev = DEV_CPU;
        sess = new_session(DEV_CPU, -1);
        if (!sess) return 4;
        snprintf(dev_txt + strlen(dev_txt), sizeof dev_txt - strlen(dev_txt), ", ab Abschnitt %d CPU", nr + 1);
        rs = run_segment(sess, g_mem, in, res, NULL);
      }
      if (ort_fail(rs, "Trennen")) return 5;
      long skip = off - st;
      for (int s = 0; s < NSRC; s++) {
        /* htdemucs_ft: jedes Modell liefert nur "seinen" Stem */
        if (nmodels > 1 && s != mi) continue;
        for (int c = 0; c < 2; c++) {
          const float *src = res + ((size_t)s * 2 + c) * SEG + skip;
          float *dst = out + ((size_t)s * 2 + c) * n + off;
          for (long k = 0; k < len; k++) dst[k] += w[k] * src[k];
        }
      }
      if (mi == 0) for (long k = 0; k < len; k++) wsum[off + k] += w[k];
      nr++;
      say("%s%s[THREAD 0] (%7.3f%%) Abschnitt %d von %d\n", prefix, tab, 100.0 * nr / chunks, nr, chunks);
    }
    t_sep += now_s() - ts;
    g_ort->ReleaseSession(sess);
    free_weights(&wt);
  }

  /* --- Normalisierung rückgängig machen und speichern --- */
  CreateDirectoryW(out_dir, NULL);
  float *l = malloc(sizeof(float) * n), *r = malloc(sizeof(float) * n);
  for (int s = 0; s < NSRC; s++) {
    for (long i = 0; i < n; i++) {
      l[i] = out[((size_t)s * 2 + 0) * n + i] / wsum[i] * std + mean;
      r[i] = out[((size_t)s * 2 + 1) * n + i] / wsum[i] * std + mean;
    }
    size_t L = wcslen(out_dir);
    int sep = L > 0 && (out_dir[L - 1] == L'\\' || out_dir[L - 1] == L'/');
    swprintf(p, MAX_PATH * 2, L"%ls%lstarget_%d_%hs.wav", out_dir, sep ? L"" : L"\\", s, SRC_NAMES[s]);
    say("Writing wav file %s\n", u8(p));
    if (!write_wav(p, l, r, n)) return 6;
  }

  double audio_min = n / (double)SR / 60.0;
  say("\nFertig.\n  Gerät        : %s\n  Modell laden : %.1f s\n  Trennen      : %.1f s\n"
      "  Audio        : %.1f s\n  => %.1f Sekunden Rechenzeit pro Audiominute\n",
      dev_txt, t_load, t_sep, n / (double)SR, t_sep / audio_min);
  if (ergebnis) {
    FILE *e = _wfopen(ergebnis, L"a");
    if (e) {
      fprintf(e, "StemOnnx %s | %s | Modell %s | Gerät %s | Laden %.1f s | Trennen %.1f s | Audio %.1f s | "
                 "%.1f s pro Audiominute | gesamt %.1f s\n",
              STEMONNX_VERSION, u8(wav_path), nmodels > 1 ? "htdemucs_ft" : "htdemucs", dev_txt,
              t_load, t_sep, n / (double)SR, t_sep / audio_min, now_s() - t0);
      fclose(e);
    }
  }
  return 0;
}
