task :setup_ac_db do
  Rake::Task[:load_cip_data].invoke("data/alamedaco.json")
end

