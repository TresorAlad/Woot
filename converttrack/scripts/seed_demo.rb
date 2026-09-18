# frozen_string_literal: true

# Seed demo mockups ConvertTrack sur le compte admin.
# Usage: rails runner /app/converttrack/scripts/seed_demo.rb

$stdout.sync = true

require Rails.root.join('lib/converttrack/demo_seeder')

Converttrack::DemoSeeder.perform!
