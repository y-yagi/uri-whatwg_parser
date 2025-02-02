# Uri::WhatwgParser

Ruby implementation of the [WHATWG URL Living Standard](https://url.spec.whatwg.org/).

The latest revision that this package implements of the standard is ([24 March 2025](https://url.spec.whatwg.org/commit-snapshots/cc8b776b89a6d92b5cc74581c8d90450d3c1e762/)).

NOTE: Some features haven't been implemented yet. Please see the TODO for details.

## Installation

```bash
gem install uri-whatwg_parser
```

## Usage

This gem is compatible with [`uri`](https://github.com/ruby/uri) gem and automatically switches parser's behavior. So users don't need to set up.

```ruby
URI.parse("http://日本語.jp")
# => #<URI::HTTP http://xn--wgv71a119e.jp>
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake test` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## TODO

* Support passing `base`
* Support state override
* Support validations
* Support encodings other than UTF-8

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/y-yagi/uri-whatwg_parser.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
