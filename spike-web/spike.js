// Shared setup for the two spike pages. Development environment only.
const $ = id => document.getElementById(id);
const say = line => { $('log').textContent = new Date().toLocaleTimeString() + '  ' + line + '\n' + $('log').textContent; console.log('[spike]', line); };
CloudKit.configure({
  containers: [{
    containerIdentifier: 'iCloud.com.outandscout.app',
    apiTokenAuth: { apiToken: window.CK_TOKEN, persist: true,
      signInButton: { id: 'apple-sign-in-button', theme: 'black' },
      signOutButton: { id: 'apple-sign-out-button', theme: 'black' } },
    environment: 'development'
  }]
});
const container = CloudKit.getDefaultContainer();
