#!/bin/bash

# Accurate Step Counter - Test Runner Script
# This script helps run comprehensive tests for the step counter plugin

set -e

echo "🧪 Accurate Step Counter - Test Runner"
echo "========================================"
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

# Check if device is connected
check_device() {
    print_info "Checking for connected Android device..."

    if ! command -v adb &> /dev/null; then
        print_error "ADB not found. Please install Android SDK Platform Tools."
        exit 1
    fi

    DEVICE_COUNT=$(adb devices | grep -w "device" | wc -l)

    if [ "$DEVICE_COUNT" -eq 0 ]; then
        print_error "No Android device connected. Please connect a device or start an emulator."
        exit 1
    fi

    print_success "Android device connected"
    adb devices | grep -w "device"
}

# Check Android version
check_android_version() {
    print_info "Checking Android version..."

    API_LEVEL=$(adb shell getprop ro.build.version.sdk)
    ANDROID_VERSION=$(adb shell getprop ro.build.version.release)

    echo "   Android Version: $ANDROID_VERSION (API $API_LEVEL)"

    if [ "$API_LEVEL" -ge 30 ]; then
        print_success "Android 11+ detected - Will use native step detector with OS-level sync"
    elif [ "$API_LEVEL" -le 29 ]; then
        print_warning "Android 10 or below - Will use foreground service for background counting"
    fi
}

# Build and install app
build_and_install() {
    print_info "Building and installing example app..."

    cd example

    flutter clean > /dev/null 2>&1
    print_success "Cleaned build artifacts"

    flutter pub get > /dev/null 2>&1
    print_success "Dependencies resolved"

    print_info "Building APK (this may take a minute)..."
    flutter build apk --debug > build.log 2>&1

    if [ $? -eq 0 ]; then
        print_success "APK built successfully"
    else
        print_error "Build failed. Check build.log for details"
        exit 1
    fi

    print_info "Installing on device..."
    flutter install > /dev/null 2>&1
    print_success "App installed"

    cd ..
}

# Grant permissions
grant_permissions() {
    print_info "Granting required permissions..."

    PACKAGE="com.example.accurate_step_counter_example"

    # Activity recognition
    adb shell pm grant $PACKAGE android.permission.ACTIVITY_RECOGNITION 2>/dev/null || print_warning "Could not grant ACTIVITY_RECOGNITION (may need to do manually)"

    # Notification (Android 13+)
    adb shell pm grant $PACKAGE android.permission.POST_NOTIFICATIONS 2>/dev/null || print_warning "POST_NOTIFICATIONS not needed on this Android version"

    # Body sensors
    adb shell pm grant $PACKAGE android.permission.BODY_SENSORS 2>/dev/null || print_warning "Could not grant BODY_SENSORS (optional)"

    print_success "Permissions granted"
}

# Watch logs
watch_logs() {
    print_info "Starting log monitoring (press Ctrl+C to stop)..."
    echo ""

    adb logcat -c
    adb logcat -s AccurateStepCounter NativeStepDetector StepSync StepForegroundService
}

# Run specific scenario
run_scenario() {
    SCENARIO=$1

    echo ""
    print_info "Running Scenario $SCENARIO"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    case $SCENARIO in
        1)
            echo "📱 Scenario 1: Morning Walk (Foreground)"
            echo "   1. Open the app"
            echo "   2. Walk 100 steps"
            echo "   3. Observe real-time updates"
            echo "   4. Check logs below"
            ;;
        2)
            echo "📱 Scenario 2: Background Mode"
            echo "   1. Open the app, walk 50 steps"
            echo "   2. Press home button"
            echo "   3. Walk 50 more steps"
            echo "   4. Return to app and verify"
            ;;
        3)
            echo "📱 Scenario 3: Terminated State Recovery"
            echo "   1. Open the app, walk 30 steps"
            echo "   2. Force stop: adb shell am force-stop com.example.accurate_step_counter_example"
            echo "   3. Walk 50 steps"
            echo "   4. Open app and check for sync"
            ;;
        4)
            echo "📱 Scenario 4: All-Day Tracking"
            echo "   1. Follow steps in TESTING_SCENARIOS.md"
            echo "   2. Test mixed states throughout the day"
            ;;
        5)
            echo "📱 Scenario 5: Running Workout"
            echo "   1. Configure running preset"
            echo "   2. Run for 1 minute"
            echo "   3. Verify higher cadence handling"
            ;;
        *)
            print_error "Unknown scenario. Choose 1-5"
            exit 1
            ;;
    esac

    echo ""
    print_info "Press Enter to start log monitoring..."
    read

    watch_logs
}

# Check sensor availability
check_sensors() {
    print_info "Checking available sensors..."

    adb shell dumpsys sensorservice | grep -i "step" > /dev/null 2>&1

    if [ $? -eq 0 ]; then
        print_success "Step sensors available on device"
        adb shell dumpsys sensorservice | grep -i "step" | head -5
    else
        print_warning "Could not detect step sensors (may still work)"
    fi
}

# Main menu
show_menu() {
    echo ""
    echo "Choose an option:"
    echo "  1) Quick Setup (build, install, grant permissions)"
    echo "  2) Run Scenario Test (1-5)"
    echo "  3) Watch Logs Only"
    echo "  4) Check Device Info"
    echo "  5) Grant Permissions"
    echo "  6) Open Testing Guide"
    echo "  7) Exit"
    echo ""
    echo -n "Enter choice [1-7]: "
}

# Main script
main() {
    check_device
    echo ""

    while true; do
        show_menu
        read choice

        case $choice in
            1)
                build_and_install
                grant_permissions
                print_success "Setup complete! You can now test the app."
                ;;
            2)
                echo -n "Which scenario (1-5)? "
                read scenario
                run_scenario $scenario
                ;;
            3)
                watch_logs
                ;;
            4)
                check_android_version
                check_sensors
                ;;
            5)
                grant_permissions
                ;;
            6)
                if [ -f "TESTING_SCENARIOS.md" ]; then
                    print_info "Opening testing guide..."
                    open "TESTING_SCENARIOS.md" 2>/dev/null || cat "TESTING_SCENARIOS.md" | less
                else
                    print_error "TESTING_SCENARIOS.md not found"
                fi
                ;;
            7)
                print_info "Goodbye!"
                exit 0
                ;;
            *)
                print_error "Invalid choice. Please enter 1-7."
                ;;
        esac
    done
}

# Run main
main
