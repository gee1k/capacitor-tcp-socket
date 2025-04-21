import { SplashScreen } from '@capacitor/splash-screen';
import { TcpSocket } from 'capacitor-tcp-socket';

// 定义支持的数据编码
const DataEncoding = {
  UTF8: 'utf8',
  BASE64: 'base64',
  HEX: 'hex'
};

window.customElements.define(
  'capacitor-welcome',
  class extends HTMLElement {
    constructor() {
      super();

      SplashScreen.hide();

      const root = this.attachShadow({ mode: 'open' });

      root.innerHTML = `
    <style>
      :host {
        font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif, "Apple Color Emoji", "Segoe UI Emoji", "Segoe UI Symbol";
        display: block;
        width: 100%;
        height: 100%;
      }
      h1, h2, h3, h4, h5 {
        text-transform: uppercase;
      }
      .button {
        display: inline-block;
        padding: 10px;
        background-color: #73B5F6;
        color: #fff;
        font-size: 0.9em;
        border: 0;
        border-radius: 3px;
        text-decoration: none;
        cursor: pointer;
        margin: 5px;
        min-width: 120px;
      }
      .button:disabled {
        opacity: 0.5;
        cursor: not-allowed;
      }
      main {
        padding: 15px;
      }
      .form-group {
        margin-bottom: 16px;
      }
      .form-group label {
        display: block;
        margin-bottom: 6px;
        font-weight: bold;
      }
      .form-group input, .form-group select, .form-group textarea {
        width: 100%;
        padding: 8px;
        border: 1px solid #ddd;
        border-radius: 4px;
        box-sizing: border-box;
        font-family: inherit;
      }
      .form-group textarea {
        height: 80px;
        resize: vertical;
        font-family: monospace;
      }
      .button-group {
        display: flex;
        flex-wrap: wrap;
        gap: 8px;
        margin-bottom: 20px;
      }
      .panel {
        border: 1px solid #ddd;
        border-radius: 4px;
        padding: 16px;
        margin-bottom: 20px;
      }
      .panel-title {
        margin-top: 0;
        padding-bottom: 10px;
        border-bottom: 1px solid #eee;
      }
      .log-area {
        background: #f5f5f5;
        border: 1px solid #ddd;
        border-radius: 4px;
        padding: 12px;
        font-family: monospace;
        height: 200px;
        overflow-y: auto;
        white-space: pre-wrap;
        word-break: break-all;
      }
      .log-entry {
        margin-bottom: 6px;
        border-bottom: 1px dotted #ddd;
        padding-bottom: 6px;
      }
      .log-time {
        color: #666;
        font-size: 0.9em;
      }
      .log-message {
        display: block;
        margin-top: 2px;
      }
      .log-error {
        color: #d9534f;
      }
      .log-success {
        color: #5cb85c;
      }
      .tabs {
        display: flex;
        border-bottom: 2px solid #ddd;
        margin-bottom: 20px;
      }
      .tab {
        padding: 10px 16px;
        cursor: pointer;
        margin-right: 5px;
        border-bottom: 2px solid transparent;
        margin-bottom: -2px;
      }
      .tab.active {
        border-bottom-color: #73B5F6;
        font-weight: bold;
      }
      .tab-content {
        display: none;
      }
      .tab-content.active {
        display: block;
      }
      .encoding-info {
        font-size: 0.85em;
        color: #666;
        margin-top: 4px;
      }
      .status-indicator {
        display: inline-block;
        width: 10px;
        height: 10px;
        border-radius: 50%;
        margin-right: 6px;
      }
      .status-connected {
        background-color: #5cb85c;
      }
      .status-disconnected {
        background-color: #d9534f;
      }
      .status-text {
        font-size: 0.9em;
      }
      .clear-log {
        font-size: 0.9em;
        margin-left: auto;
        background: transparent;
        border: none;
        color: #73B5F6;
        cursor: pointer;
      }
      .log-header {
        display: flex;
        align-items: center;
        margin-bottom: 8px;
      }
    </style>
    <div>
      <capacitor-welcome-titlebar>
        <h1>TCP Socket Demo</h1>
      </capacitor-welcome-titlebar>
      <main>
        <div class="panel">
          <h2 class="panel-title">Connection Status</h2>
          <div>
            <span class="status-indicator status-disconnected" id="status-indicator"></span>
            <span class="status-text" id="status-text">Disconnected</span>
          </div>
        </div>
        
        <div class="tabs">
          <div class="tab active" data-tab="connect">Connect</div>
          <div class="tab" data-tab="send">Send</div>
          <div class="tab" data-tab="receive">Receive</div>
          <div class="tab" data-tab="info">Info</div>
        </div>
        
        <!-- Connection Tab -->
        <div class="tab-content active" id="connect-tab">
          <div class="form-group">
            <label for="ip-address">Server IP Address</label>
            <input type="text" id="ip-address" value="127.0.0.1" placeholder="e.g., 192.168.1.100">
          </div>
          
          <div class="form-group">
            <label for="port">Server Port</label>
            <input type="number" id="port" value="9100" placeholder="e.g., 9100">
          </div>
          
          <div class="button-group">
            <button class="button" id="connect-btn">Connect</button>
            <button class="button" id="disconnect-btn" disabled>Disconnect</button>
          </div>
        </div>
        
        <!-- Send Tab -->
        <div class="tab-content" id="send-tab">
          <div class="form-group">
            <label for="send-encoding">Encoding</label>
            <select id="send-encoding">
              <option value="utf8">UTF-8 (Text)</option>
              <option value="base64">Base64 (Binary)</option>
              <option value="hex">Hexadecimal</option>
            </select>
          </div>
          
          <div class="form-group">
            <label for="send-data">Data to Send</label>
            <textarea id="send-data" placeholder="Enter data to send...">Hello TCP Server!</textarea>
            <div class="encoding-info" id="send-encoding-info">Enter text data in UTF-8 format</div>
          </div>
          
          <div class="button-group">
            <button class="button" id="send-btn" disabled>Send Data</button>
          </div>
        </div>
        
        <!-- Receive Tab -->
        <div class="tab-content" id="receive-tab">
          <div class="form-group">
            <label for="read-encoding">Preferred Encoding</label>
            <select id="read-encoding">
              <option value="utf8">UTF-8 (Text)</option>
              <option value="base64">Base64 (Binary)</option>
              <option value="hex">Hexadecimal</option>
            </select>
          </div>
          
          <div class="form-group">
            <label for="read-length">Max Bytes to Read</label>
            <input type="number" id="read-length" value="1024" min="1">
          </div>
          
          <div class="form-group">
            <label for="read-timeout">Timeout (seconds, iOS only)</label>
            <input type="number" id="read-timeout" value="5" min="1">
          </div>
          
          <div class="button-group">
            <button class="button" id="read-btn" disabled>Read Data</button>
          </div>
          
          <div class="form-group">
            <label for="received-data">Received Data</label>
            <textarea id="received-data" readonly placeholder="Received data will appear here..."></textarea>
            <div class="encoding-info" id="received-encoding-info"></div>
          </div>
        </div>
        
        <!-- Info Tab -->
        <div class="tab-content" id="info-tab">
          <h2>About TCP Socket Plugin</h2>
          <p>
            This demo demonstrates the capabilities of the Capacitor TCP Socket plugin.
            You can use this plugin to establish TCP connections from your Capacitor app.
          </p>
          
          <h3>Features:</h3>
          <ul>
            <li>Connect to TCP servers</li>
            <li>Send data with different encodings (UTF-8, Base64, Hex)</li>
            <li>Receive data with preferred encoding</li>
            <li>Binary data support</li>
          </ul>
          
          <h3>Usage Tips:</h3>
          <ul>
            <li>Start by connecting to a TCP server in the Connect tab</li>
            <li>When sending binary data, convert it to Base64 or Hex first</li>
            <li>For receiving binary data, use Base64 or Hex encoding</li>
            <li>The plugin automatically handles encoding conversion</li>
          </ul>
          
          <p>
            <a href="https://github.com/gee1k/capacitor-tcp-socket" target="_blank" class="button">GitHub Repo</a>
          </p>
        </div>
        
        <div class="panel">
          <div class="log-header">
            <h2 class="panel-title">Activity Log</h2>
            <button class="clear-log" id="clear-log">Clear Log</button>
          </div>
          <div class="log-area" id="log-area"></div>
        </div>
      </main>
    </div>
    `;
    }

    connectedCallback() {
      // Store client ID for connected socket
      let clientId = null;
      
      // Get DOM elements
      const tabs = this.shadowRoot.querySelectorAll('.tab');
      const tabContents = this.shadowRoot.querySelectorAll('.tab-content');
      const logArea = this.shadowRoot.querySelector('#log-area');
      const statusIndicator = this.shadowRoot.querySelector('#status-indicator');
      const statusText = this.shadowRoot.querySelector('#status-text');
      
      // Form elements
      const ipAddressInput = this.shadowRoot.querySelector('#ip-address');
      const portInput = this.shadowRoot.querySelector('#port');
      const sendEncodingSelect = this.shadowRoot.querySelector('#send-encoding');
      const sendDataInput = this.shadowRoot.querySelector('#send-data');
      const sendEncodingInfo = this.shadowRoot.querySelector('#send-encoding-info');
      const readEncodingSelect = this.shadowRoot.querySelector('#read-encoding');
      const readLengthInput = this.shadowRoot.querySelector('#read-length');
      const readTimeoutInput = this.shadowRoot.querySelector('#read-timeout');
      const receivedDataArea = this.shadowRoot.querySelector('#received-data');
      const receivedEncodingInfo = this.shadowRoot.querySelector('#received-encoding-info');
      
      // Buttons
      const connectBtn = this.shadowRoot.querySelector('#connect-btn');
      const disconnectBtn = this.shadowRoot.querySelector('#disconnect-btn');
      const sendBtn = this.shadowRoot.querySelector('#send-btn');
      const readBtn = this.shadowRoot.querySelector('#read-btn');
      const clearLogBtn = this.shadowRoot.querySelector('#clear-log');
      
      // Tab switching
      tabs.forEach(tab => {
        tab.addEventListener('click', () => {
          tabs.forEach(t => t.classList.remove('active'));
          tabContents.forEach(tc => tc.classList.remove('active'));
          
          tab.classList.add('active');
          const tabId = tab.getAttribute('data-tab');
          this.shadowRoot.querySelector(`#${tabId}-tab`).classList.add('active');
        });
      });
      
      // Helper function to log messages
      const log = (message, type = 'info') => {
        const logEntry = document.createElement('div');
        logEntry.classList.add('log-entry');
        if (type === 'error') logEntry.classList.add('log-error');
        if (type === 'success') logEntry.classList.add('log-success');
        
        const time = new Date().toLocaleTimeString();
        logEntry.innerHTML = `
          <span class="log-time">[${time}]</span>
          <span class="log-message">${message}</span>
        `;
        
        logArea.appendChild(logEntry);
        logArea.scrollTop = logArea.scrollHeight;
      };
      
      // Update encoding info based on selection
      const updateSendEncodingInfo = () => {
        const encoding = sendEncodingSelect.value;
        switch(encoding) {
          case DataEncoding.UTF8:
            sendEncodingInfo.textContent = 'Enter text data in UTF-8 format';
            break;
          case DataEncoding.BASE64:
            sendEncodingInfo.textContent = 'Enter Base64-encoded binary data';
            break;
          case DataEncoding.HEX:
            sendEncodingInfo.textContent = 'Enter hexadecimal data (e.g. "48656C6C6F" for "Hello")';
            break;
        }
      };
      
      // Update connection status
      const updateConnectionStatus = (connected) => {
        if (connected) {
          statusIndicator.className = 'status-indicator status-connected';
          statusText.textContent = `Connected (Client ID: ${clientId})`;
          connectBtn.disabled = true;
          disconnectBtn.disabled = false;
          sendBtn.disabled = false;
          readBtn.disabled = false;
        } else {
          statusIndicator.className = 'status-indicator status-disconnected';
          statusText.textContent = 'Disconnected';
          connectBtn.disabled = false;
          disconnectBtn.disabled = true;
          sendBtn.disabled = true;
          readBtn.disabled = true;
          clientId = null;
        }
      };
      
      // Connect to server
      connectBtn.addEventListener('click', async () => {
        const ipAddress = ipAddressInput.value.trim();
        const port = parseInt(portInput.value, 10);
        
        if (!ipAddress) {
          log('IP address is required', 'error');
          return;
        }
        
        log(`Connecting to ${ipAddress}:${port}...`);
        
        try {
          const result = await TcpSocket.connect({ ipAddress, port });
          clientId = result.client;
          log(`Connected to ${ipAddress}:${port}. Client ID: ${clientId}`, 'success');
          updateConnectionStatus(true);
        } catch (error) {
          log(`Connection failed: ${error.message}`, 'error');
        }
      });
      
      // Disconnect from server
      disconnectBtn.addEventListener('click', async () => {
        if (clientId === null) {
          log('Not connected to any server', 'error');
          return;
        }
        
        log('Disconnecting...');
        
        try {
          await TcpSocket.disconnect({ client: clientId });
          log('Disconnected successfully', 'success');
          updateConnectionStatus(false);
        } catch (error) {
          log(`Disconnect failed: ${error.message}`, 'error');
        }
      });
      
      // Send data
      sendBtn.addEventListener('click', async () => {
        if (clientId === null) {
          log('Not connected to any server', 'error');
          return;
        }
        
        const data = sendDataInput.value;
        const encoding = sendEncodingSelect.value;
        
        if (!data) {
          log('Data to send is empty', 'error');
          return;
        }
        
        log(`Sending data with ${encoding} encoding...`);
        
        try {
          await TcpSocket.send({
            client: clientId,
            data,
            encoding
          });
          log('Data sent successfully', 'success');
        } catch (error) {
          log(`Failed to send data: ${error.message}`, 'error');
        }
      });
      
      // Read data
      readBtn.addEventListener('click', async () => {
        if (clientId === null) {
          log('Not connected to any server', 'error');
          return;
        }
        
        const expectLen = parseInt(readLengthInput.value, 10);
        const timeout = parseInt(readTimeoutInput.value, 10);
        const encoding = readEncodingSelect.value;
        
        log(`Reading data with ${encoding} encoding (max ${expectLen} bytes)...`);
        
        try {
          const result = await TcpSocket.read({
            client: clientId,
            expectLen,
            timeout,
            encoding
          });
          
          const receivedEncoding = result.encoding || encoding;
          
          if (result.result) {
            log(`Received data with ${receivedEncoding} encoding`, 'success');
            receivedDataArea.value = result.result;
            receivedEncodingInfo.textContent = `Data encoded as: ${receivedEncoding}`;
          } else {
            log('No data received or empty response', 'error');
            receivedDataArea.value = '';
            receivedEncodingInfo.textContent = '';
          }
        } catch (error) {
          log(`Failed to read data: ${error.message}`, 'error');
          receivedDataArea.value = '';
          receivedEncodingInfo.textContent = '';
        }
      });
      
      // Clear log
      clearLogBtn.addEventListener('click', () => {
        logArea.innerHTML = '';
      });
      
      // Update encoding info when selection changes
      sendEncodingSelect.addEventListener('change', updateSendEncodingInfo);
      
      // Initialize encoding info
      updateSendEncodingInfo();
      
      // Log initial message
      log('TCP Socket Demo initialized. Ready to connect.');
    }
  },
);

window.customElements.define(
  'capacitor-welcome-titlebar',
  class extends HTMLElement {
    constructor() {
      super();
      const root = this.attachShadow({ mode: 'open' });
      root.innerHTML = `
    <style>
      :host {
        position: relative;
        display: block;
        padding: 15px 15px 15px 15px;
        text-align: center;
        background-color: #73B5F6;
      }
      ::slotted(h1) {
        margin: 0;
        font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif, "Apple Color Emoji", "Segoe UI Emoji", "Segoe UI Symbol";
        font-size: 0.9em;
        font-weight: 600;
        color: #fff;
      }
    </style>
    <slot></slot>
    `;
    }
  },
);
