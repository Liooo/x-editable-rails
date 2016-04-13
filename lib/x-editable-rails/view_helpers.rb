require 'base64'

module X
  module Editable
    module Rails
      module ViewHelpers
        #
        # Options determine how the HTML tag is rendered and the remaining options are converted to data-* attributes.
        #
        # options:
        #   tag:   tag name of element returned
        #   class: "class" attribute on element
        #   placeholder: "placeholder" attribute on element
        #   title: "title" attribute on element (defaults to placeholder)
        #   data:  "data-*" attributes on element
        #     source: a Hash of friendly display values used by input elements based on (object) value
        #       - boolean shorthand ['Enabled', 'Disabled'] becomes { '1' => 'Enabled', '0' => 'Disabled' }
        #       - enumerable shorthand ['Yes', 'No', 'Maybe'] becomes { 'Yes' => 'Yes', 'No' => 'No', 'Maybe' => 'Maybe' }
        #     classes: a Hash of classes to add based on the value (same format and shorthands as source)
        #   value: override the object's value
        #
        def editable(object, method, options = {})
          options = Configuration.method_options_for(object, method).deep_merge(options).with_indifferent_access
          # merge data attributes for backwards-compatibility
          options.merge! options.delete(:data){ Hash.new }

          url     = options.delete(:url){ polymorphic_path(object) }
          object  = object.last if object.kind_of?(Array)
          nested  = options.delete(:nested)
          deepest_obj = nested ? dig_nested_obj(object, nested) : object
          attr_error = deepest_obj.errors[method]
          value = options.delete(:value){ deepest_obj.send(method) }
          value_type  = deepest_obj.class.columns_hash[method.to_s].type
          source  = options[:source] ?
            (options[:source].is_a? String)? options.delete(:source) : format_source(options.delete(:source), value_type)
            : default_source_for(value_type)
          classes = format_source(options.delete(:classes), value_type)
          error   = options.delete(:e)
          html_options = options.delete(:html){ Hash.new }

          if xeditable?(object)
            model   = object.class.model_name.element
            nid     = options.delete(:nid)
            title   = options.delete(:title) do
              if nested
                klass = nested.is_a?(Array) ? object.class.const_get(nested.last.keys.first.to_s.classify) : object.class.const_get(nested.keys.first.to_s.classify)
              else
                klass = object.class
              end
              klass.human_attribute_name(method)
            end

            output_value = output_value_for(value)
            css_list = options.delete(:class).to_s.split(/\s+/).unshift('editable')
            css_list << classes[output_value] if classes
            type = options.delete(:type){ default_type_for(value) }
            css   = css_list.compact.uniq.join(' ')
            tag   = options.delete(:tag){ 'span' }
            placeholder = options.delete(:placeholder){ title }

            # any remaining options become data attributes
            data  = {
              type:   type,
              model:  model,
              name:   method,
              value:  ( type == 'wysihtml5' ? Base64.encode64(output_value) : output_value ),
              placeholder: placeholder,
              classes: classes,
              source: source,
              url:    url,
              nested: nested,
              nid:    nid,
              'attr-error' => attr_error.present? ? attr_error : nil,
              container: options.delete(:container){ 'body' }
            }.merge(options.symbolize_keys)

            data.reject!{|_, value| value.nil?}

            html_options.update({
              class: css,
              title: title,
              data: data
            })

            content_tag tag, html_options do
              if %w(select checklist).include? data[:type].to_s
                if(source.is_a? String)
                  content = value
                else
                  source = normalize_source(source)
                  content = source.detect { |t| output_value == output_value_for(t[0]) }
                  content.present? ? content[1] : ""
                end
              else
                safe_join(source_values_for(value, value_type, source), tag(:br))
              end
            end
          else
            error || safe_join(source_values_for(value, value_type, source), tag(:br))
          end
        end

        private

        def normalize_source(source)
          source.map do |el|
            if el.is_a? Array
              el
            else
              [el[:value], el[:text]]
            end
          end
        end

        def output_value_for(value)
          value = case value
          when TrueClass
            '1'
          when FalseClass
            '0'
          when NilClass
            ''
          when Array
            value.map{|item| output_value_for item}.join(',')
          else
            value.to_s
          end

          value
        end

        def source_values_for(value, value_type, source = nil)
          source ||= default_source_for(value_type)

          values = Array.wrap(value)

          if source && ( source.first.is_a?(String) || source.kind_of?(Hash) )
            values.map{|item| source[output_value_for item]}
          else
            values
          end
        end

        def default_type_for(value)
          case value
          when TrueClass, FalseClass
            'select'
          when Array
            'checklist'
          else
            'text'
          end
        end

        def default_source_for(value_type)
          case value_type
          when :boolean
            { '1' => 'Yes', '0' => 'No' }
          end
        end

        def dig_nested_obj(obj, nested)
          case(nested)
            when Array
              err_obj = nested.inject(obj){|memo, n|
                attr = n.keys.first
                id = n.values.first
                case(memo.class.reflect_on_association(attr))
                  when ActiveRecord::Reflection::HasOneReflection
                    memo = memo.send(attr)
                  when ActiveRecord::Reflection::HasManyReflection
                    memo = memo.send(attr).detect{|o| o.id == id}
                end
                memo
              }
            when Hash
              attr = nested.keys.first
              id = nested.values.first
              err_obj = case(obj.class.reflect_on_association(attr))
                when ActiveRecord::Reflection::HasOneReflection
                  obj.send(attr)
                when ActiveRecord::Reflection::HasManyReflection
                  obj.send(attr).detect{|o| o.id == id}
              end
          end
          return err_obj
        end

        # helper method that take some shorthand source definitions and reformats them
        def format_source(source, value_type)
          formatted_source = case value_type
            when :boolean
              if source.is_a?(Array) && source.first.is_a?(String) && source.size == 2
                { '1' => source[0], '0' => source[1] }
              end
            when :string
              if source.is_a?(Array)
                if source.first.is_a?(String)
                  source.inject({}){|hash, key| hash.merge(key => key)}
                elsif source.first.is_a?(Array) && source.first.size == 2
                  # handle rails form helpers collection
                  source.inject({}){|hash, key| hash.merge(key[1] => key[0])}
                end
              elsif source.is_a?(Hash)
                source
              end
            end

          formatted_source || source
        end

      end
    end
  end
end
