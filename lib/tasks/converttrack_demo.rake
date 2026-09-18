# frozen_string_literal: true

namespace :converttrack do
  desc 'Seed demo mockups for ConvertTrack (admin account only)'
  task seed_demo: :environment do
    require Rails.root.join('lib/converttrack/demo_seeder')
    Converttrack::DemoSeeder.perform!
  end
end
