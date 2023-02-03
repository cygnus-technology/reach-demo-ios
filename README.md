# Reach Sample iOS App

The Reach Sample iOS app is a demo of how you can use Cygnus Reach to enable support sessions in your app. This demo app allows you to connect to a Bluetooth device and send its data via a Cygnus session to a web portal (https://portal.cygnusreach.com/).

## Setting Up

1. Open up Terminal, navigate to the project directory and run `pod install`
2. Select the project file in the project navigator and set your team in the Signing & Capabilities section. Change the bundle ID as needed
3. Navigate to the ProductService class and add in your Cygnus API key in the empty apiKey variable string

## Using the App

Start a support session by tapping the Start a Support Session button, or connect to a device and then start a session from the connected device view. Generate a PIN in the web app using the same product key as the one pasted in the app, then enter that PIN in the PIN screen in the app and tap Continue
