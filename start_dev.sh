#!/bin/bash

# LiveAiChat Development Server Startup Script
# This script loads environment variables from dev.env and starts the Phoenix server
# Logs are written to a temporary file in /tmp.

LOG_DIR="/tmp"
LOG_FILE="$LOG_DIR/elix-live-chat-start_dev.log"

SPEED_MODE="compile"
if [ "$1" == "fast" ]; then
    SPEED_MODE="skip_compile"
fi

echo "🚀 Starting LiveAiChat Development Server in $SPEED_MODE mode..."

# Check if dev.env exists
if [ ! -f "dev.env" ]; then
    echo "❌ Error: dev.env file not found!"
    echo "Please create dev.env with your Google OAuth credentials:"
    echo "GOOGLE_CLIENT_ID=your_client_id_here"
    echo "GOOGLE_CLIENT_SECRET=your_client_secret_here"
    exit 1
fi

# Load environment variables
echo "📁 Loading environment variables from dev.env..."
set -a  # Automatically export all variables
source dev.env
set +a  # Turn off automatic export

# Verify required variables are set
if [ -z "$GOOGLE_CLIENT_ID" ] || [ -z "$GOOGLE_CLIENT_SECRET" ]; then
    echo "❌ Error: Missing required Google OAuth credentials!"
    echo "Please set GOOGLE_CLIENT_ID and GOOGLE_CLIENT_SECRET in dev.env"
    exit 1
fi

echo "✅ Google OAuth credentials loaded"
if [ "$SPEED_MODE" == "compile" ]; then
    echo "📦 Installing dependencies..."
    mix deps.get

    echo "🔨 Compiling application..."
    mix compile
else
    echo "🔨 Skipping dependency installation and compilation..."
fi

export PORT=4000

echo "🌐 Starting Phoenix server at http://localhost:$PORT"
echo "🔐 Authentication required - visit http://localhost:$PORT/login to sign in"
echo "Press Ctrl+C to stop the server"
echo ""

echo "📝 Logging to: $LOG_FILE"

mix phx.server | tee "$LOG_FILE"