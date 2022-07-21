#! /usr/bin/env ruby

require 'pg'
require 'io/console'

class ExpenseData
  def initialize
    @connection = PG.connect(dbname: "expenses")
    setup_schema
  end

  def list_expenses
    results = @connection.exec('SELECT * FROM expenses ORDER BY created_on ASC;')
    display_count(results)
    display_expenses(results) if results.ntuples > 0
  end
  
  def add_expense(amount, memo)
    @connection.exec_params(
      "INSERT INTO expenses (amount, memo, created_on) VALUES ($1, $2, now())",
      [amount, memo]
    )
  end

  def search_expenses(query)
    results = @connection.exec_params(
      "SELECT * FROM expenses WHERE memo ILIKE $1",
      ["%#{query}%"]
    )
    display_count(results)
    display_expenses(results)
  end

  def delete_expense(id)
    results = @connection.exec_params(
      "SELECT * FROM expenses WHERE id = $1",
      [id]
    )

    if results.ntuples == 0
      puts "There is no expense with the id '#{id}'."
    else
      @connection.exec_params(
        "DELETE FROM expenses WHERE id = $1",
        [id]
      )
      puts "The following expense has been deleted:"
      display_expenses(results)
    end
  end

  def delete_all_expenses
    @connection.exec('DELETE FROM expenses;')
    puts "All expenses have been deleted."
  end

  private

  def setup_schema
    results = @connection.exec <<~SQL.chomp
      SELECT COUNT(*)
      FROM information_schema.tables
      WHERE table_schema = 'public' AND table_name = 'expenses';
    SQL

    if results.field_values("count")[0] == "0"
      @connection.exec <<~SQL.chomp
        CREATE TABLE expenses (
        id serial PRIMARY KEY,
        amount decimal(6, 2) NOT NULL CHECK (amount >= 0.01),
        memo text NOT NULL,
        created_on date NOT NULL
        );
      SQL
    end
  end

  def display_expenses(expenses)
    expenses.each_row do |id, amount, memo, created_on|
      puts [id.rjust(3), created_on.rjust(10), amount.rjust(12), memo].join(' | ') 
    end

    puts '-' * 50

    expenses_total = expenses.field_values("amount").map(&:to_f).inject(:+)
    puts ("Total " + ("%.2f" % expenses_total).rjust(25))
  end

  def display_count(results)
    case results.ntuples
    when 0 then puts "There are no expenses."
    when 1 then puts "There is 1 expense."
    when (2..) then puts "There are #{results.ntuples} expenses."
    end
  end
end

class CLI
  def initialize
    @application = ExpenseData.new 
  end

  def run(args)
    command = args.first
    case command
    when 'list'
      @application.list_expenses
    when 'add'
      amount, memo = args[1, 2]
      abort("You must provide an amount and memo.") unless amount && memo
      @application.add_expense(amount, memo)
    when 'search'
      query = args[1]
      abort("You must provide a query.") unless query
      @application.search_expenses(query)
    when 'delete'
      id = args[1]
      abort("You must provide an id.") unless id
      @application.delete_expense(id)
    when 'clear'
      puts "This will remove all expenses. Are you sure? (y/N)"
      answer = $stdin.getch
      abort if answer != 'y'
      @application.delete_all_expenses
    else
      display_help
    end
  end

  def display_help
    puts <<~HELP
      An expense recording system
  
      Commands:
  
      add AMOUNT MEMO [DATE] - record a new expense
      clear - delete all expenses
      list - list all expenses
      delete NUMBER - remove expense with id NUMBER
      search QUERY - list expenses with a matching memo field
    HELP
  end
end

cli = CLI.new
cli.run(ARGV)