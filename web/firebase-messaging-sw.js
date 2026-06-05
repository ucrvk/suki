/* eslint-disable no-undef */
importScripts('https://www.gstatic.com/firebasejs/10.13.2/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.13.2/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'AIzaSyAMIOFxm_xyANj0EjQA0U5rnvw-ikSe7HM',
  appId: '1:1016491984372:web:14579b6cc61e5c1a5665a1',
  messagingSenderId: '1016491984372',
  projectId: 'suki-get',
  authDomain: 'suki-get.firebaseapp.com',
  storageBucket: 'suki-get.firebasestorage.app',
  measurementId: 'G-S6QPQZ3H6N',
});

const messaging = firebase.messaging();

messaging.onBackgroundMessage((payload) => {
  const notification = payload.notification || {};
  const title = notification.title || 'suki';
  const options = {
    body: notification.body || '',
    icon: '/icons/Icon-192.png',
    badge: '/icons/Icon-192.png',
    data: payload.data || {},
  };

  self.registration.showNotification(title, options);
});
