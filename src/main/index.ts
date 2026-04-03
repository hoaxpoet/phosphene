import { app, BrowserWindow } from 'electron';
import { spawn, ChildProcess } from 'child_process';
import * as path from 'path';

let mainWindow: BrowserWindow | null = null;
let audioTapProcess: ChildProcess | null = null;

function createWindow(): void {
  mainWindow = new BrowserWindow({
    width: 1280,
    height: 720,
    backgroundColor: '#000000',
    webPreferences: {
      nodeIntegration: true,
      contextIsolation: false,
    },
    show: true,
  });

  mainWindow.loadFile(path.join(__dirname, '..', 'renderer', 'index.html'));

  // Forward renderer console logs to main process stdout (for diagnostics)
  mainWindow.webContents.on('console-message', (_event, _level, message) => {
    if (message.startsWith('[ONSET') || message.startsWith('[BEAT DIAG]') || message.startsWith('[BASS PULSE]') || message.startsWith('[FFT]') || message.startsWith('[FEATURES]')) {
      console.log(message);
    }
  });

  mainWindow.on('closed', () => {
    mainWindow = null;
    stopAudioCapture();
  });

  // Keyboard shortcuts
  mainWindow.webContents.on('before-input-event', (_event, input) => {
    if (!input.alt && !input.control && !input.meta) {
      if (input.key === 'f' && mainWindow) {
        mainWindow.setFullScreen(!mainWindow.isFullScreen());
      }
      if (input.key === 'n' && mainWindow) {
        mainWindow.webContents.send('next-scene');
      }
    }
  });
}

function startAudioCapture(): void {
  // Use our native ScreenCaptureKit audio_tap binary to capture system audio
  // It streams raw float32 stereo PCM at 48kHz to stdout
  const tapPath = path.join(__dirname, '..', '..', 'assets', 'audio_tap');
  console.log('[Phosphene:main] Starting audio capture:', tapPath);

  audioTapProcess = spawn(tapPath, [], {
    stdio: ['pipe', 'pipe', 'pipe'],
  });

  audioTapProcess.stderr!.on('data', (data: Buffer) => {
    console.log('[Phosphene:main] audio_tap:', data.toString().trim());
  });

  audioTapProcess.on('error', (err: Error) => {
    console.error('[Phosphene:main] audio_tap error:', err.message);
  });

  audioTapProcess.on('close', (code: number) => {
    console.log('[Phosphene:main] audio_tap exited:', code);
  });

  // Forward raw float32 PCM chunks to the renderer via IPC
  let chunkCount = 0;
  let totalBytes = 0;
  audioTapProcess.stdout!.on('data', (chunk: Buffer) => {
    chunkCount++;
    totalBytes += chunk.length;
    if (chunkCount <= 3 || chunkCount % 500 === 0) {
      console.log(`[Phosphene:main] Audio chunk #${chunkCount}: ${chunk.length} bytes (total: ${totalBytes})`);
    }
    if (mainWindow && !mainWindow.isDestroyed()) {
      mainWindow.webContents.send('audio-data', chunk);
    }
  });
}

function stopAudioCapture(): void {
  if (audioTapProcess) {
    audioTapProcess.kill();
    audioTapProcess = null;
  }
}

app.whenReady().then(() => {
  createWindow();
  startAudioCapture();
});

app.on('window-all-closed', () => {
  stopAudioCapture();
  app.quit();
});
