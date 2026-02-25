// Give the service worker access to Firebase Messaging.
// Note that you can only use Firebase Messaging here. Other Firebase libraries
// are not available in the service worker.
importScripts('https://www.gstatic.com/firebasejs/10.7.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.7.0/firebase-messaging-compat.js');

// Initialize the Firebase app in the service worker by passing in
// your app's Firebase config object.
// https://firebase.google.com/docs/web/setup#config-object
firebase.initializeApp({
    apiKey: 'AIzaSyA7ORjHBjmeCttl8YpWVE5SJMxCZlx-ubI',
    appId: '1:350226436436:web:c32b395f7523c91e2eb8c1',
    messagingSenderId: '350226436436',
    projectId: 'sentinel-sumatra-3c917',
    authDomain: 'sentinel-sumatra-3c917.firebaseapp.com',
    storageBucket: 'sentinel-sumatra-3c917.firebasestorage.app',
    measurementId: 'G-5M7VC176YL'
});

// Retrieve an instance of Firebase Messaging so that it can handle background
// messages.
const messaging = firebase.messaging();

messaging.onBackgroundMessage((payload) => {
    console.log('[firebase-messaging-sw.js] Received background message ', payload);
    const notificationTitle = payload.notification.title;
    const notificationOptions = {
        body: payload.notification.body,
        icon: '/icons/Icon-192.png'
    };

    self.registration.showNotification(notificationTitle, notificationOptions);
});
